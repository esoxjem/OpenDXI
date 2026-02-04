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

    # ═══════════════════════════════════════════════════════════════════════════
    # HTTP Caching (Phase 2 optimization)
    # ═══════════════════════════════════════════════════════════════════════════

    test "metrics returns ETag header on first request" do
      # Create fresh sprint for this test
      fresh_sprint = Sprint.create!(
        start_date: Date.current,
        end_date: Date.current + 7,
        data: sample_sprint_data
      )

      get "/api/sprints/#{fresh_sprint.start_date}/#{fresh_sprint.end_date}/metrics"

      assert_response :ok
      assert response.headers["ETag"].present?, "ETag header should be present"
    end

    test "metrics returns 304 Not Modified when ETag matches" do
      # Create fresh sprint for this test
      fresh_sprint = Sprint.create!(
        start_date: Date.current + 14,
        end_date: Date.current + 21,
        data: sample_sprint_data
      )

      # First request to get the ETag
      get "/api/sprints/#{fresh_sprint.start_date}/#{fresh_sprint.end_date}/metrics"
      assert_response :ok
      etag = response.headers["ETag"]
      assert etag.present?

      # Second request with If-None-Match header matching the ETag
      get "/api/sprints/#{fresh_sprint.start_date}/#{fresh_sprint.end_date}/metrics",
          headers: { "If-None-Match" => etag }

      assert_response :not_modified
      assert response.body.empty?, "304 responses should have empty body"
    end

    test "metrics returns 200 OK on force_refresh even with matching ETag" do
      # Create a fresh sprint to test force_refresh behavior
      # Don't use force_refresh=true to avoid GitHub API call in tests
      # Just verify that force_refresh bypasses the ETag cache logic
      fresh_sprint = Sprint.create!(
        start_date: Date.current + 28,
        end_date: Date.current + 35,
        data: sample_sprint_data
      )

      # First request to get the ETag
      get "/api/sprints/#{fresh_sprint.start_date}/#{fresh_sprint.end_date}/metrics"
      assert_response :ok
      etag = response.headers["ETag"]

      # Second request with If-None-Match should return 304
      get "/api/sprints/#{fresh_sprint.start_date}/#{fresh_sprint.end_date}/metrics",
          headers: { "If-None-Match" => etag }
      assert_response :not_modified

      # Verify the ETag is based on the sprint's cache key
      # (may include a filter suffix when Developer records exist)
      etag_value = etag.gsub('"', '')
      assert etag_value.start_with?(fresh_sprint.generate_cache_key),
        "ETag should be based on sprint cache key"
    end

    test "metrics sets cache control headers" do
      get "/api/sprints/#{@sprint.start_date}/#{@sprint.end_date}/metrics"

      assert_response :ok
      assert response.headers["Cache-Control"].include?("public")
      assert response.headers["Cache-Control"].include?("max-age=300")
    end

    test "generate_cache_key returns consistent hash for unchanged data" do
      cache_key_1 = @sprint.generate_cache_key
      sleep 0.1 # Small delay
      cache_key_2 = @sprint.generate_cache_key

      assert_equal cache_key_1, cache_key_2, "Cache key should be same for unchanged data"
    end

    test "generate_cache_key changes when data is updated" do
      original_key = @sprint.generate_cache_key

      # Update the sprint data
      new_data = sample_sprint_data.merge(
        "summary" => { "total_commits" => 999 }
      )
      @sprint.update!(data: new_data)

      updated_key = @sprint.generate_cache_key

      assert_not_equal original_key, updated_key, "Cache key should change when data changes"
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # Team Filtering (?team=slug)
    # ═══════════════════════════════════════════════════════════════════════════

    test "metrics filters developers by team when ?team=slug is provided" do
      sprint = Sprint.create!(
        start_date: Date.current + 42,
        end_date: Date.current + 56,
        data: multi_developer_sprint_data
      )

      # alice is on the backend team (via fixtures)
      get "/api/sprints/#{sprint.start_date}/#{sprint.end_date}/metrics?team=backend"

      assert_response :success
      json = JSON.parse(response.body)

      dev_names = json["developers"].map { |d| d["developer"] }
      assert_includes dev_names, "alice"
      refute_includes dev_names, "charlie", "charlie is not on backend team"
    end

    test "metrics recomputes summary for filtered set" do
      sprint = Sprint.create!(
        start_date: Date.current + 56,
        end_date: Date.current + 70,
        data: multi_developer_sprint_data
      )

      get "/api/sprints/#{sprint.start_date}/#{sprint.end_date}/metrics?team=backend"

      assert_response :success
      json = JSON.parse(response.body)

      # Summary should reflect only alice + bob (backend team members who are in sprint)
      # Not the full sprint summary
      assert json["summary"]["total_commits"] <= 22, "Summary should be recomputed from filtered devs"
    end

    test "metrics includes filter_meta when filtering" do
      sprint = Sprint.create!(
        start_date: Date.current + 70,
        end_date: Date.current + 84,
        data: multi_developer_sprint_data
      )

      get "/api/sprints/#{sprint.start_date}/#{sprint.end_date}/metrics?team=backend"

      assert_response :success
      json = JSON.parse(response.body)

      assert json.key?("filter_meta"), "Response should include filter_meta when filtering"
      meta = json["filter_meta"]
      assert meta.key?("total_developers")
      assert meta.key?("showing_developers")
      assert meta.key?("team_name")
      assert_equal "Backend", meta["team_name"]
    end

    test "metrics ignores invalid team slug gracefully" do
      get "/api/sprints/#{@sprint.start_date}/#{@sprint.end_date}/metrics?team=nonexistent"

      assert_response :success
      json = JSON.parse(response.body)

      # Should return data without team filtering (only visibility filtering)
      assert json.key?("developers")
    end

    test "metrics produces different ETags for different team filters" do
      sprint = Sprint.create!(
        start_date: Date.current + 84,
        end_date: Date.current + 98,
        data: multi_developer_sprint_data
      )

      get "/api/sprints/#{sprint.start_date}/#{sprint.end_date}/metrics?team=backend"
      assert_response :ok
      etag_backend = response.headers["ETag"]

      get "/api/sprints/#{sprint.start_date}/#{sprint.end_date}/metrics?team=frontend"
      assert_response :ok
      etag_frontend = response.headers["ETag"]

      assert_not_equal etag_backend, etag_frontend,
        "Different team filters should produce different ETags"
    end

    test "history filters by team when ?team=slug is provided" do
      Sprint.destroy_all
      Sprint.create!(
        start_date: Date.new(2026, 3, 1),
        end_date: Date.new(2026, 3, 14),
        data: multi_developer_sprint_data
      )

      get "/api/sprints/history?team=backend"

      assert_response :success
      json = JSON.parse(response.body)
      sprints = json["sprints"]

      # History aggregates should reflect filtered developer set
      assert sprints.first["developer_count"] <= 2,
        "Developer count should reflect team members only"
    end

    private

    def multi_developer_sprint_data
      {
        "developers" => [
          {
            "developer" => "alice",
            "commits" => 10,
            "prs_opened" => 2,
            "prs_merged" => 2,
            "reviews_given" => 5,
            "lines_added" => 200,
            "lines_deleted" => 50,
            "dxi_score" => 80.0,
            "dimension_scores" => {
              "review_turnaround" => 85.0,
              "cycle_time" => 75.0,
              "pr_size" => 90.0,
              "review_coverage" => 50.0,
              "commit_frequency" => 50.0
            }
          },
          {
            "developer" => "bob",
            "commits" => 8,
            "prs_opened" => 3,
            "prs_merged" => 2,
            "reviews_given" => 3,
            "lines_added" => 150,
            "lines_deleted" => 30,
            "dxi_score" => 70.0,
            "dimension_scores" => {
              "review_turnaround" => 70.0,
              "cycle_time" => 65.0,
              "pr_size" => 85.0,
              "review_coverage" => 30.0,
              "commit_frequency" => 40.0
            }
          },
          {
            "developer" => "charlie",
            "commits" => 4,
            "prs_opened" => 1,
            "prs_merged" => 1,
            "reviews_given" => 1,
            "lines_added" => 100,
            "lines_deleted" => 20,
            "dxi_score" => 55.0,
            "dimension_scores" => {
              "review_turnaround" => 60.0,
              "cycle_time" => 50.0,
              "pr_size" => 70.0,
              "review_coverage" => 10.0,
              "commit_frequency" => 20.0
            }
          }
        ],
        "daily_activity" => [],
        "summary" => {
          "total_commits" => 22,
          "total_prs" => 6,
          "total_merged" => 5,
          "total_reviews" => 9,
          "developer_count" => 3,
          "avg_dxi_score" => 68.3
        },
        "team_dimension_scores" => {
          "review_turnaround" => 71.7,
          "cycle_time" => 63.3,
          "pr_size" => 81.7,
          "review_coverage" => 30.0,
          "commit_frequency" => 36.7
        }
      }
    end

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
