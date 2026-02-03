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
  # OAuth Callback (create) - Database-based authorization
  # ═══════════════════════════════════════════════════════════════════════════

  test "create allows login for registered user" do
    # Pre-register the user in the database
    user = User.create!(
      github_id: 12345,
      login: "testuser",
      name: "Test User",
      avatar_url: "https://github.com/testuser.png"
    )

    mock_github_auth(github_id: user.github_id, login: user.login, name: user.name, avatar_url: user.avatar_url)

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

  test "create rejects unregistered user" do
    # User NOT in database
    mock_github_auth(github_id: 99999, login: "unregistereduser", name: "Unregistered", avatar_url: "https://github.com/unreg.png")

    get "/auth/github/callback"

    assert_response :redirect
    assert_match(/error=not_authorized/, response.location)

    # Verify session was NOT created
    get "/api/auth/me"
    assert_response :unauthorized
  end

  test "create bootstraps owner when OWNER_GITHUB_USERNAME matches and no owners exist" do
    ENV["OWNER_GITHUB_USERNAME"] = "bootstrapowner"

    # Ensure no owners exist
    User.where(role: :owner).destroy_all

    mock_github_auth(github_id: 777777, login: "bootstrapowner", name: "Bootstrap Owner", avatar_url: "https://github.com/bootstrap.png")

    get "/auth/github/callback"

    assert_response :redirect
    refute_match(/error=/, response.location)

    # Verify user was created as owner
    user = User.find_by(github_id: 777777)
    assert user.present?, "User should have been created"
    assert user.owner?, "User should be owner"
  ensure
    ENV.delete("OWNER_GITHUB_USERNAME")
  end

  test "create does not bootstrap owner if owners already exist" do
    ENV["OWNER_GITHUB_USERNAME"] = "wouldbeowner"

    # Ensure an owner exists
    User.find_or_create_by!(github_id: 111111, login: "existingowner") do |u|
      u.name = "Existing Owner"
      u.avatar_url = "https://github.com/existingowner.png"
      u.role = :owner
    end

    mock_github_auth(github_id: 888888, login: "wouldbeowner", name: "Would Be Owner", avatar_url: "https://github.com/wouldbe.png")

    get "/auth/github/callback"

    # Should be rejected since user is not in database and bootstrap condition not met
    assert_response :redirect
    assert_match(/error=not_authorized/, response.location)

    # User should NOT have been created
    assert_nil User.find_by(github_id: 888888)
  ensure
    ENV.delete("OWNER_GITHUB_USERNAME")
  end

  test "create updates last_login_at for existing user" do
    user = User.create!(
      github_id: 12345,
      login: "testuser",
      name: "Test User",
      avatar_url: "https://github.com/testuser.png",
      last_login_at: nil
    )

    mock_github_auth(github_id: user.github_id, login: user.login, name: user.name, avatar_url: user.avatar_url)

    freeze_time do
      get "/auth/github/callback"

      user.reload
      assert_equal Time.current, user.last_login_at
    end
  end

  test "create stores authenticated_at timestamp in session" do
    user = User.create!(
      github_id: 12345,
      login: "testuser",
      name: "Test User",
      avatar_url: "https://github.com/testuser.png"
    )

    mock_github_auth(github_id: user.github_id, login: user.login, name: user.name, avatar_url: user.avatar_url)

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

  test "deleting user from database revokes access immediately" do
    # Sign in as a specific user
    user = sign_in_as(login: "testuser", name: "Test User", github_id: 12345, avatar_url: "https://github.com/test.png")

    # Verify authenticated
    get "/api/auth/me"
    assert_response :success

    # Now delete the user from database (simulating owner removing them)
    user.destroy!

    # Next request should be rejected
    get "/api/auth/me"
    assert_response :unauthorized
    json = JSON.parse(response.body)
    assert_equal false, json["authenticated"]
    assert_equal "access_revoked", json["error"]
  end
end
