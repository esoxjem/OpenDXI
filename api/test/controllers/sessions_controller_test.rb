# frozen_string_literal: true

require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  # ═══════════════════════════════════════════════════════════════════════════
  # Login Page (new)
  # ═══════════════════════════════════════════════════════════════════════════

  test "login page renders when not authenticated" do
    get login_path
    assert_response :success
    assert_select "h1", /OpenDXI Dashboard/
  end

  test "login page redirects to dashboard when already authenticated" do
    sign_in_as
    get login_path
    assert_response :redirect
    assert_redirected_to root_path
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Logout (destroy)
  # ═══════════════════════════════════════════════════════════════════════════

  test "destroy clears session and redirects to login" do
    sign_in_as

    delete "/auth/logout"

    assert_response :redirect
    assert_redirected_to login_path
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

  test "create sets session and redirects to dashboard on successful OAuth" do
    mock_github_auth

    get "/auth/github/callback"

    assert_response :redirect
    assert_redirected_to root_path
  end

  test "create rejects unauthorized user when allowed_users configured" do
    original_allowed_users = Rails.application.config.opendxi.allowed_users
    Rails.application.config.opendxi.allowed_users = ["otheruser"]

    mock_github_auth  # testuser is not in allowed list

    get "/auth/github/callback"

    assert_response :redirect
    assert_match(/error=not_authorized/, response.location)
  ensure
    Rails.application.config.opendxi.allowed_users = original_allowed_users
  end

  test "create allows any user when allowed_users is empty" do
    original_allowed_users = Rails.application.config.opendxi.allowed_users
    Rails.application.config.opendxi.allowed_users = []

    mock_github_auth

    get "/auth/github/callback"

    assert_response :redirect
    refute_match(/error=/, response.location)
  ensure
    Rails.application.config.opendxi.allowed_users = original_allowed_users
  end
end

# ═══════════════════════════════════════════════════════════════════════════
# Session Security Tests (expiration and authorization)
# ═══════════════════════════════════════════════════════════════════════════

class SessionSecurityTest < ActionDispatch::IntegrationTest
  setup do
    # Create a sprint in the database so dashboard doesn't need to fetch from GitHub
    create_test_sprint
  end

  test "dashboard requires authentication" do
    get root_path
    assert_response :redirect
    assert_redirected_to login_path
  end

  test "dashboard accessible when authenticated" do
    sign_in_as
    get root_path
    assert_response :success
  end

  test "session expires after 24 hours" do
    sign_in_as

    get root_path
    assert_response :success

    travel 25.hours do
      get root_path
      assert_response :redirect
      assert_redirected_to login_path
    end
  end

  test "session remains valid within 24 hours" do
    sign_in_as

    travel 23.hours do
      get root_path
      assert_response :success
    end
  end

  private

  def create_test_sprint
    # Create sprint for current period to avoid GitHub fetch
    start_date, end_date = Sprint.current_sprint_dates
    Sprint.find_or_create_by!(start_date: start_date, end_date: end_date) do |s|
      s.data = {
        "developers" => [
          {
            "github_login" => "testdev",
            "commits" => 10,
            "prs_opened" => 2,
            "prs_merged" => 2,
            "reviews_given" => 5,
            "dxi_score" => 75.0,
            "dimension_scores" => {
              "review_turnaround" => 80.0,
              "cycle_time" => 70.0,
              "pr_size" => 75.0,
              "review_coverage" => 80.0,
              "commit_frequency" => 70.0
            }
          }
        ],
        "daily_activity" => [],
        "summary" => {
          "total_commits" => 10,
          "total_prs" => 2,
          "total_merged" => 2,
          "total_reviews" => 5,
          "avg_dxi_score" => 75.0
        },
        "team_dimension_scores" => {
          "review_turnaround" => 80.0,
          "cycle_time" => 70.0,
          "pr_size" => 75.0,
          "review_coverage" => 80.0,
          "commit_frequency" => 70.0
        }
      }
    end
  end
end
