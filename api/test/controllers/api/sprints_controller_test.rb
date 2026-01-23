# frozen_string_literal: true

require "test_helper"

module Api
  class SprintsControllerTest < ActionDispatch::IntegrationTest
    setup do
      # Authenticate before each test
      sign_in_as

      @sprint = Sprint.create!(
        start_date: Date.current - 7,
        end_date: Date.current + 7,
        data: sample_sprint_data
      )
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # Date::Error Handling (P1-004)
    # ═══════════════════════════════════════════════════════════════════════════

    test "metrics returns 400 for invalid start_date format" do
      get "/api/sprints/invalid-date/2026-01-20/metrics"

      assert_response :bad_request
      json = JSON.parse(response.body)
      assert_equal "bad_request", json["error"]
    end

    test "metrics returns 400 for invalid end_date format" do
      get "/api/sprints/2026-01-07/not-a-date/metrics"

      assert_response :bad_request
      json = JSON.parse(response.body)
      assert_equal "bad_request", json["error"]
    end

    test "metrics returns 400 for completely invalid dates" do
      get "/api/sprints/foo/bar/metrics"

      assert_response :bad_request
      json = JSON.parse(response.body)
      assert_equal "bad_request", json["error"]
    end

    test "metrics returns 200 for valid date formats" do
      get "/api/sprints/#{@sprint.start_date}/#{@sprint.end_date}/metrics"

      assert_response :success
      json = JSON.parse(response.body)
      assert json.key?("developers"), "Response should contain developers key"
      assert json.key?("summary"), "Response should contain summary key"
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # Basic Functionality
    # ═══════════════════════════════════════════════════════════════════════════

    test "index returns list of sprints" do
      get "/api/sprints"

      assert_response :success
      json = JSON.parse(response.body)
      assert json.key?("sprints")
      assert_kind_of Array, json["sprints"]
    end

    test "history returns sprint history" do
      get "/api/sprints/history"

      assert_response :success
      json = JSON.parse(response.body)
      assert json.key?("sprints")
    end

    test "history returns sprints in chronological order (oldest first)" do
      # Create additional sprints with known dates
      Sprint.destroy_all

      old_sprint = Sprint.create!(
        start_date: Date.new(2026, 1, 1),
        end_date: Date.new(2026, 1, 14),
        data: sample_sprint_data
      )
      middle_sprint = Sprint.create!(
        start_date: Date.new(2026, 1, 15),
        end_date: Date.new(2026, 1, 28),
        data: sample_sprint_data
      )
      new_sprint = Sprint.create!(
        start_date: Date.new(2026, 1, 29),
        end_date: Date.new(2026, 2, 11),
        data: sample_sprint_data
      )

      get "/api/sprints/history"

      assert_response :success
      json = JSON.parse(response.body)
      sprints = json["sprints"]

      # Should be ordered oldest→newest for proper trend display
      assert_equal 3, sprints.length
      assert_equal "2026-01-01", sprints.first["start_date"]
      assert_equal "2026-01-29", sprints.last["start_date"]

      # Verify chronological ordering throughout
      dates = sprints.map { |s| Date.parse(s["start_date"]) }
      assert_equal dates.sort, dates, "Sprints should be in chronological order (oldest first)"
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
end
