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

  test "should get show" do
    get root_path
    assert_response :success
    assert_select "h2", @sprint.label
  end

  test "show renders team tab by default" do
    get dashboard_path
    assert_response :success
    # Should have KPI cards
    assert_select "[data-testid='kpi-card']", minimum: 4
  end

  test "show renders developers tab when requested" do
    get dashboard_path(view: "developers", sprint: @sprint.date_range_param)
    assert_response :success
    assert_select "table"
  end

  test "show with sprint param loads specific sprint" do
    past_sprint = Sprint.create!(
      start_date: Date.current - 30,
      end_date: Date.current - 16,
      data: sample_sprint_data
    )

    get dashboard_path(sprint: past_sprint.date_range_param)
    assert_response :success
    assert_select "h2", past_sprint.label
  end

  test "refresh redirects to dashboard on HTML request" do
    post dashboard_refresh_path(sprint: @sprint.date_range_param)
    assert_response :redirect
    assert_match %r{/dashboard}, response.location
  end

  test "refresh responds with turbo_stream on turbo request" do
    post dashboard_refresh_path(sprint: @sprint.date_range_param),
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_match "turbo-stream", response.content_type
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # View Parameter Whitelist (P1-003)
  # ═══════════════════════════════════════════════════════════════════════════

  test "show defaults to team view for invalid view parameter" do
    get dashboard_path(view: "invalid", sprint: @sprint.date_range_param)
    assert_response :success
    # Should render team tab, not fail or render invalid partial
    assert_select "[data-testid='kpi-card']", minimum: 4
  end

  test "show defaults to team view for path traversal attempt" do
    get dashboard_path(view: "../../../etc/passwd", sprint: @sprint.date_range_param)
    assert_response :success
    # Should safely fall back to team view
    assert_select "[data-testid='kpi-card']", minimum: 4
  end

  test "show allows valid team view" do
    get dashboard_path(view: "team", sprint: @sprint.date_range_param)
    assert_response :success
  end

  test "show allows valid developers view" do
    get dashboard_path(view: "developers", sprint: @sprint.date_range_param)
    assert_response :success
    assert_select "table"
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
          "dimension_scores" => {
            "review_turnaround" => 80.0,
            "cycle_time" => 70.0,
            "pr_size" => 90.0,
            "review_coverage" => 50.0,
            "commit_frequency" => 50.0
          }
        }
      ],
      "daily_activity" => [],
      "summary" => {
        "total_commits" => 10,
        "total_prs" => 2,
        "total_merged" => 2,
        "total_reviews" => 5,
        "developer_count" => 1,
        "avg_dxi_score" => 75.0
      },
      "team_dimension_scores" => {
        "review_turnaround" => 80.0,
        "cycle_time" => 70.0,
        "pr_size" => 90.0,
        "review_coverage" => 50.0,
        "commit_frequency" => 50.0
      }
    }
  end
end
