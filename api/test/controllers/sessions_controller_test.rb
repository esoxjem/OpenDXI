# frozen_string_literal: true

require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  # ═══════════════════════════════════════════════════════════════════════════
  # Logout (destroy)
  # ═══════════════════════════════════════════════════════════════════════════

  test "destroy clears session and redirects to login" do
    # First, log in via test helper
    sign_in_as

    # Verify logged in
    get "/api/auth/me"
    assert_response :success

    # Now log out
    delete "/auth/logout"

    assert_response :redirect
    assert_match %r{/login\z}, response.location

    # Verify logged out
    get "/api/auth/me"
    assert_response :unauthorized
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Failure
  # ═══════════════════════════════════════════════════════════════════════════

  test "failure redirects to login with error message" do
    get "/auth/failure", params: { message: "access_denied" }

    assert_response :redirect
    assert_match(/error=access_denied/, response.location)
  end

  test "failure uses unknown_error when no message provided" do
    get "/auth/failure"

    assert_response :redirect
    assert_match(/error=unknown_error/, response.location)
  end
  # ═══════════════════════════════════════════════════════════════════════════
  # OAuth Callback (create) - Using OmniAuth mock
  # ═══════════════════════════════════════════════════════════════════════════

  test "create sets session and redirects on successful OAuth" do
    mock_github_auth

    get "/auth/github/callback"

    assert_response :redirect
    assert_match ENV.fetch("FRONTEND_URL", "http://localhost:3001"), response.location

    # Verify session was created by checking auth status
    get "/api/auth/me"
    assert_response :success
    json = JSON.parse(response.body)
    assert json["authenticated"]
    assert_equal "testuser", json["user"]["login"]
    assert_equal "Test User", json["user"]["name"]
  end

  test "create rejects unauthorized user when allowed_users configured" do
    # Configure allowed users to NOT include our test user
    original_allowed_users = Rails.application.config.opendxi.allowed_users
    Rails.application.config.opendxi.allowed_users = ["otheruser"]

    mock_github_auth  # testuser is not in allowed list

    get "/auth/github/callback"

    assert_response :redirect
    assert_match(/error=not_authorized/, response.location)

    # Verify session was NOT created
    get "/api/auth/me"
    assert_response :unauthorized
  ensure
    Rails.application.config.opendxi.allowed_users = original_allowed_users
  end

  test "create allows any user when allowed_users is empty" do
    # Ensure allowed users is empty
    original_allowed_users = Rails.application.config.opendxi.allowed_users
    Rails.application.config.opendxi.allowed_users = []

    mock_github_auth

    get "/auth/github/callback"

    assert_response :redirect
    refute_match(/error=/, response.location)

    # Verify session was created
    get "/api/auth/me"
    assert_response :success
  ensure
    Rails.application.config.opendxi.allowed_users = original_allowed_users
  end

  test "create stores authenticated_at timestamp in session" do
    mock_github_auth

    freeze_time do
      get "/auth/github/callback"
      assert_response :redirect

      # The session should have authenticated_at set
      # We verify this indirectly by checking the session is valid
      get "/api/auth/me"
      assert_response :success
    end
  end
end

# ═══════════════════════════════════════════════════════════════════════════
# Session Security Tests (expiration and authorization revocation)
# ═══════════════════════════════════════════════════════════════════════════

class SessionSecurityTest < ActionDispatch::IntegrationTest
  test "session expires after 24 hours" do
    # Sign in
    sign_in_as

    # Verify authenticated
    get "/api/auth/me"
    assert_response :success

    # Travel forward 25 hours
    travel 25.hours do
      get "/api/auth/me"
      assert_response :unauthorized
      json = JSON.parse(response.body)
      assert_equal false, json["authenticated"]
    end
  end

  test "session remains valid within 24 hours" do
    # Sign in
    sign_in_as

    # Travel forward 23 hours (still within limit)
    travel 23.hours do
      get "/api/auth/me"
      assert_response :success
    end
  end

  test "removing user from allowed_users revokes access immediately" do
    original_allowed_users = Rails.application.config.opendxi.allowed_users

    # Start with testuser in allowed list
    Rails.application.config.opendxi.allowed_users = ["testuser"]

    # Sign in as testuser
    sign_in_as(login: "testuser", name: "Test User", github_id: 12345, avatar_url: "https://github.com/test.png")

    # Verify authenticated
    get "/api/auth/me"
    assert_response :success

    # Now remove testuser from allowed list
    Rails.application.config.opendxi.allowed_users = ["otheruser"]

    # Next request should be rejected
    get "/api/auth/me"
    assert_response :unauthorized
    json = JSON.parse(response.body)
    assert_equal false, json["authenticated"]
    assert_equal "access_revoked", json["error"]
  ensure
    Rails.application.config.opendxi.allowed_users = original_allowed_users
  end

  test "user remains authorized when allowed_users becomes empty" do
    original_allowed_users = Rails.application.config.opendxi.allowed_users

    # Start with testuser in allowed list
    Rails.application.config.opendxi.allowed_users = ["testuser"]

    # Sign in
    sign_in_as(login: "testuser", name: "Test User", github_id: 12345, avatar_url: "https://github.com/test.png")

    # Verify authenticated
    get "/api/auth/me"
    assert_response :success

    # Make allowed_users empty (allow everyone)
    Rails.application.config.opendxi.allowed_users = []

    # User should still be authorized
    get "/api/auth/me"
    assert_response :success
  ensure
    Rails.application.config.opendxi.allowed_users = original_allowed_users
  end
end
