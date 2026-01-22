# frozen_string_literal: true

require "test_helper"

module Api
  class DevelopersControllerTest < ActionDispatch::IntegrationTest
    setup do
      # Create multiple sprints with different developers
      @sprint1 = Sprint.create!(
        start_date: Date.current - 14,
        end_date: Date.current - 7,
        data: {
          "developers" => [
            { "developer" => "alice", "commits" => 10, "dxi_score" => 75.0 },
            { "developer" => "bob", "commits" => 8, "dxi_score" => 70.0 }
          ],
          "daily_activity" => [],
          "summary" => { "developer_count" => 2 },
          "team_dimension_scores" => {}
        }
      )

      @sprint2 = Sprint.create!(
        start_date: Date.current - 7,
        end_date: Date.current,
        data: {
          "developers" => [
            { "developer" => "alice", "commits" => 12, "dxi_score" => 80.0 },
            { "developer" => "charlie", "commits" => 5, "dxi_score" => 65.0 }
          ],
          "daily_activity" => [],
          "summary" => { "developer_count" => 2 },
          "team_dimension_scores" => {}
        }
      )
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # GET /api/developers (index)
    # ═══════════════════════════════════════════════════════════════════════════

    test "index returns list of unique developer names" do
      get "/api/developers"

      assert_response :success
      json = JSON.parse(response.body)

      assert json.key?("developers"), "Response should contain developers key"
      assert_kind_of Array, json["developers"]
      assert_equal %w[alice bob charlie], json["developers"]
    end

    test "index returns developers sorted alphabetically" do
      get "/api/developers"

      assert_response :success
      json = JSON.parse(response.body)

      # Verify the list is sorted
      assert_equal json["developers"].sort, json["developers"]
    end

    test "index respects sprint_count parameter" do
      # Create a third older sprint with a unique developer
      Sprint.create!(
        start_date: Date.current - 21,
        end_date: Date.current - 14,
        data: {
          "developers" => [
            { "developer" => "dave", "commits" => 3, "dxi_score" => 60.0 }
          ],
          "daily_activity" => [],
          "summary" => { "developer_count" => 1 },
          "team_dimension_scores" => {}
        }
      )

      # Request only 2 sprints (should exclude dave from the oldest sprint)
      get "/api/developers?sprint_count=2"

      assert_response :success
      json = JSON.parse(response.body)

      assert_includes json["developers"], "alice"
      assert_includes json["developers"], "bob"
      assert_includes json["developers"], "charlie"
      refute_includes json["developers"], "dave"
    end

    test "index limits sprint_count to maximum of 12" do
      get "/api/developers?sprint_count=100"

      assert_response :success
      json = JSON.parse(response.body)

      # Should still return results (just clamped to max 12)
      assert json.key?("developers")
    end

    test "index handles empty database gracefully" do
      Sprint.destroy_all

      get "/api/developers"

      assert_response :success
      json = JSON.parse(response.body)

      assert_equal [], json["developers"]
    end

    test "index handles sprints with no developers" do
      Sprint.destroy_all
      Sprint.create!(
        start_date: Date.current - 7,
        end_date: Date.current,
        data: {
          "developers" => [],
          "daily_activity" => [],
          "summary" => {},
          "team_dimension_scores" => {}
        }
      )

      get "/api/developers"

      assert_response :success
      json = JSON.parse(response.body)

      assert_equal [], json["developers"]
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # GET /api/developers/:name/history (existing endpoint)
    # ═══════════════════════════════════════════════════════════════════════════

    test "history returns developer metrics across sprints" do
      get "/api/developers/alice/history"

      assert_response :success
      json = JSON.parse(response.body)

      assert json.key?("developer"), "Response should contain developer key"
      assert_equal "alice", json["developer"]
    end

    test "history returns 404 for unknown developer" do
      get "/api/developers/unknown/history"

      assert_response :not_found
    end

    test "history returns sprints in chronological order (oldest first)" do
      get "/api/developers/alice/history"

      assert_response :success
      json = JSON.parse(response.body)

      # Developer history includes both sprints (developer entries) and team_history arrays
      developer_sprints = json["sprints"]
      team_history = json["team_history"]

      # Both should be in chronological order (oldest first)
      # @sprint1 is older (Date.current - 14), @sprint2 is newer (Date.current - 7)
      assert developer_sprints.length >= 2, "Should have at least 2 sprints"

      # Verify chronological ordering
      dev_dates = developer_sprints.map { |s| Date.parse(s["start_date"]) }
      assert_equal dev_dates.sort, dev_dates, "Developer sprints should be in chronological order"

      team_dates = team_history.map { |s| Date.parse(s["start_date"]) }
      assert_equal team_dates.sort, team_dates, "Team history should be in chronological order"
    end
  end
end
