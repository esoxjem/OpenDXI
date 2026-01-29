# frozen_string_literal: true

require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    @sprint = Sprint.create!(
      start_date: Date.current - 7,
      end_date: Date.current + 7,
      data: sample_sprint_data
    )
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Authentication
  # ═══════════════════════════════════════════════════════════════════════════

  test "redirects to login when not authenticated" do
    get root_path

    assert_response :redirect
    assert_redirected_to login_path
  end

  test "redirects to login when accessing dashboard without auth" do
    get dashboard_path

    assert_response :redirect
    assert_redirected_to login_path
  end

  test "redirects to login when refreshing without auth" do
    post dashboard_refresh_path

    assert_response :redirect
    assert_redirected_to login_path
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Team Tab (default)
  # ═══════════════════════════════════════════════════════════════════════════

  test "shows team overview by default" do
    sign_in_as
    sprint_param = "#{@sprint.start_date}|#{@sprint.end_date}"

    get dashboard_path(sprint: sprint_param)

    assert_response :success
    # Check team overview section is rendered
    assert_select "[data-testid='team-overview']"
    # Check KPI cards are rendered with commit count
    assert_select "[data-testid='kpi-cards']" do
      assert_select "p", text: /Commits/i
    end
  end

  test "shows team tab when explicitly requested" do
    sign_in_as
    sprint_param = "#{@sprint.start_date}|#{@sprint.end_date}"

    get dashboard_path(tab: "team", sprint: sprint_param)

    assert_response :success
    assert_select "[data-testid='team-overview']"
  end

  test "shows leaderboard on team tab" do
    sign_in_as
    sprint_param = "#{@sprint.start_date}|#{@sprint.end_date}"

    get dashboard_path(tab: "team", sprint: sprint_param)

    assert_response :success
    assert_select "table" do
      assert_select "th", text: /Developer/i
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Developers Tab
  # ═══════════════════════════════════════════════════════════════════════════

  test "shows developers tab" do
    sign_in_as
    sprint_param = "#{@sprint.start_date}|#{@sprint.end_date}"

    get dashboard_path(tab: "developers", sprint: sprint_param)

    assert_response :success
    assert_select "[data-testid='developers-grid']"
    # Should show developer cards
    assert_select ".developer-card", count: 2
  end

  test "shows developer detail when developer is selected" do
    sign_in_as
    sprint_param = "#{@sprint.start_date}|#{@sprint.end_date}"

    get dashboard_path(tab: "developers", developer: "testuser", sprint: sprint_param)

    # Developer was found and detail view rendered
    assert_response :success
    assert_select "[data-testid='developer-detail']"
    assert_select "h2", text: /testuser/i
  end

  test "redirects on invalid developer" do
    sign_in_as
    sprint_param = "#{@sprint.start_date}|#{@sprint.end_date}"

    get dashboard_path(tab: "developers", developer: "nonexistent", sprint: sprint_param)

    # Should redirect back to developers tab with alert
    assert_response :redirect
    assert_redirected_to dashboard_path(tab: "developers", sprint: sprint_param)
    assert flash[:alert].present?
    assert_match(/Developer not found/i, flash[:alert])
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # History Tab
  # ═══════════════════════════════════════════════════════════════════════════

  test "shows history tab" do
    sign_in_as

    get dashboard_path(tab: "history")

    assert_response :success
    assert_select "[data-testid='history']"
  end

  test "shows trend chart on history tab" do
    sign_in_as
    # Create some historical sprints
    Sprint.create!(
      start_date: Date.current - 21,
      end_date: Date.current - 8,
      data: sample_sprint_data
    )

    get dashboard_path(tab: "history")

    assert_response :success
    # The history tab should render without error
    assert_select "h3", text: /DXI Trend/i
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Sprint Selection
  # ═══════════════════════════════════════════════════════════════════════════

  test "loads specific sprint when sprint param provided" do
    sign_in_as
    old_sprint = Sprint.create!(
      start_date: Date.current - 21,
      end_date: Date.current - 8,
      data: sample_sprint_data.merge(
        "summary" => sample_sprint_data["summary"].merge("total_commits" => 99)
      )
    )

    sprint_param = "#{old_sprint.start_date}|#{old_sprint.end_date}"
    get dashboard_path(sprint: sprint_param)

    assert_response :success
    # Should show the old sprint data (total commits = 99)
    assert_select "[data-testid='kpi-cards']", text: /99/
  end

  test "handles invalid sprint param gracefully" do
    sign_in_as

    get dashboard_path(sprint: "invalid|dates")

    # Should fall back to current sprint instead of erroring
    assert_response :success
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Leaderboard Sorting
  # ═══════════════════════════════════════════════════════════════════════════

  test "sorting leaderboard by dxi_score" do
    sign_in_as
    sprint_param = "#{@sprint.start_date}|#{@sprint.end_date}"

    get dashboard_path(tab: "team", sort: "dxi_score", sprint: sprint_param)

    assert_response :success
    # First developer should have higher DXI score (otheruser: 85, testuser: 75)
    assert_select "table tbody tr:first-child", text: /otheruser/
  end

  test "sorting leaderboard by commits" do
    sign_in_as
    sprint_param = "#{@sprint.start_date}|#{@sprint.end_date}"

    get dashboard_path(tab: "team", sort: "commits", sprint: sprint_param)

    assert_response :success
    # Check that the sort buttons are rendered
    assert_select "a[href*='sort=commits']"
    # First developer should have more commits (otheruser: 15, testuser: 10)
    assert_select "table tbody tr:first-child", text: /otheruser/
  end

  test "sorting leaderboard by reviews_given" do
    sign_in_as
    sprint_param = "#{@sprint.start_date}|#{@sprint.end_date}"

    get dashboard_path(tab: "team", sort: "reviews_given", sprint: sprint_param)

    assert_response :success
    # Should render without errors
    assert_select "table"
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Refresh Action
  # ═══════════════════════════════════════════════════════════════════════════

  test "refresh action requires authentication" do
    post dashboard_refresh_path

    assert_response :redirect
    assert_redirected_to login_path
  end

  test "refresh redirects back to dashboard with notice" do
    sign_in_as

    # Since the sprint already exists, find_or_fetch! will use it (no API call needed)
    post dashboard_refresh_path

    assert_response :redirect
    assert_redirected_to dashboard_path
    assert flash[:notice].present? || flash[:alert].present?
  end

  test "refresh preserves tab and sprint params" do
    sign_in_as
    sprint_param = "#{@sprint.start_date}|#{@sprint.end_date}"

    post dashboard_refresh_path(sprint: sprint_param, tab: "developers")

    assert_response :redirect
    assert_match(/tab=developers/, response.location)
    assert_match(/sprint=/, response.location)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # View Rendering
  # ═══════════════════════════════════════════════════════════════════════════

  test "renders activity chart partial" do
    sign_in_as
    sprint_param = "#{@sprint.start_date}|#{@sprint.end_date}"

    get dashboard_path(tab: "team", sprint: sprint_param)

    assert_response :success
    assert_select "h3", text: /Daily Activity/i
  end

  test "renders radar chart partial" do
    sign_in_as
    sprint_param = "#{@sprint.start_date}|#{@sprint.end_date}"

    get dashboard_path(tab: "team", sprint: sprint_param)

    assert_response :success
    assert_select "h3", text: /DXI Dimensions/i
    assert_select "canvas[data-controller='dxi-radar-chart']"
  end

  test "renders sprint selector" do
    sign_in_as
    sprint_param = "#{@sprint.start_date}|#{@sprint.end_date}"

    get dashboard_path(sprint: sprint_param)

    assert_response :success
    assert_select "[data-controller='dropdown']"
  end

  private

  def sample_sprint_data
    {
      "developers" => [
        {
          "developer" => "testuser",
          "commits" => 10,
          "prs_opened" => 2,
          "prs_merged" => 2,
          "reviews_given" => 5,
          "lines_added" => 200,
          "lines_deleted" => 50,
          "dxi_score" => 75.0,
          "avg_cycle_time_hours" => 24.5,
          "avg_review_time_hours" => 4.2,
          "dimension_scores" => {
            "review_turnaround" => 80.0,
            "cycle_time" => 70.0,
            "pr_size" => 90.0,
            "review_coverage" => 50.0,
            "commit_frequency" => 50.0
          }
        },
        {
          "developer" => "otheruser",
          "commits" => 15,
          "prs_opened" => 3,
          "prs_merged" => 3,
          "reviews_given" => 8,
          "lines_added" => 300,
          "lines_deleted" => 100,
          "dxi_score" => 85.0,
          "avg_cycle_time_hours" => 18.3,
          "avg_review_time_hours" => 3.1,
          "dimension_scores" => {
            "review_turnaround" => 90.0,
            "cycle_time" => 85.0,
            "pr_size" => 80.0,
            "review_coverage" => 75.0,
            "commit_frequency" => 70.0
          }
        }
      ],
      "daily_activity" => [
        { "date" => (Date.current - 3).to_s, "commits" => 5, "prs_merged" => 1 },
        { "date" => (Date.current - 2).to_s, "commits" => 8, "prs_merged" => 2 },
        { "date" => (Date.current - 1).to_s, "commits" => 12, "prs_merged" => 2 }
      ],
      "summary" => {
        "total_commits" => 25,
        "total_prs" => 5,
        "total_merged" => 5,
        "total_reviews" => 13,
        "developer_count" => 2,
        "avg_dxi_score" => 80.0
      },
      "team_dimension_scores" => {
        "review_turnaround" => 85.0,
        "cycle_time" => 77.5,
        "pr_size" => 85.0,
        "review_coverage" => 62.5,
        "commit_frequency" => 60.0
      }
    }
  end
end
