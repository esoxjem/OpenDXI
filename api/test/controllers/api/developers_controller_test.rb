# frozen_string_literal: true

require "test_helper"

module Api
  class DevelopersControllerTest < ActionDispatch::IntegrationTest
    setup do
      # Authenticate before each test
      sign_in_as

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
    # GET /api/developers/managed (owner-only)
    # ═══════════════════════════════════════════════════════════════════════════

    test "managed returns all developer records with teams for owner" do
      sign_in_as(role: :owner)

      get "/api/developers/managed"

      assert_response :success
      json = JSON.parse(response.body)

      assert json.key?("developers")
      devs = json["developers"]

      logins = devs.map { |d| d["github_login"] }
      assert_includes logins, "alice"
      assert_includes logins, "bob"
      assert_includes logins, "hidden-user"

      # Each developer should include team info
      alice = devs.find { |d| d["github_login"] == "alice" }
      assert alice.key?("teams")
      assert alice.key?("visible")
      assert alice.key?("source")
      assert_kind_of Array, alice["teams"]

      # Alice is on backend and frontend teams (via fixtures)
      team_names = alice["teams"].map { |t| t["name"] }
      assert_includes team_names, "Backend"
      assert_includes team_names, "Frontend"
    end

    test "managed returns developers sorted by github_login" do
      sign_in_as(role: :owner)

      get "/api/developers/managed"

      assert_response :success
      json = JSON.parse(response.body)
      logins = json["developers"].map { |d| d["github_login"] }
      assert_equal logins.sort, logins
    end

    test "managed returns 403 for non-owner" do
      sign_in_as(role: :developer)

      get "/api/developers/managed"

      assert_response :forbidden
    end

    test "managed returns 401 for unauthenticated user" do
      reset!  # Clear session from setup

      get "/api/developers/managed"

      assert_response :unauthorized
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # PATCH /api/developers/:id (owner-only)
    # ═══════════════════════════════════════════════════════════════════════════

    test "update toggles developer visibility for owner" do
      sign_in_as(role: :owner)
      dev = developers(:alice_dev)
      assert dev.visible

      patch "/api/developers/#{dev.id}", params: { developer: { visible: false } }

      assert_response :success
      json = JSON.parse(response.body)
      assert_equal false, json["developer"]["visible"]

      dev.reload
      assert_not dev.visible
    end

    test "update can make hidden developer visible" do
      sign_in_as(role: :owner)
      dev = developers(:hidden_dev)
      assert_not dev.visible

      patch "/api/developers/#{dev.id}", params: { developer: { visible: true } }

      assert_response :success
      json = JSON.parse(response.body)
      assert_equal true, json["developer"]["visible"]

      dev.reload
      assert dev.visible
    end

    test "update returns 403 for non-owner" do
      sign_in_as(role: :developer)
      dev = developers(:alice_dev)

      patch "/api/developers/#{dev.id}", params: { developer: { visible: false } }

      assert_response :forbidden
    end

    test "update returns 404 for non-existent developer" do
      sign_in_as(role: :owner)

      patch "/api/developers/999999", params: { developer: { visible: false } }

      assert_response :not_found
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # POST /api/developers/sync (owner-only)
    # ═══════════════════════════════════════════════════════════════════════════

    test "sync triggers github sync and returns summary for owner" do
      sign_in_as(role: :owner)

      mock_result = { members_synced: 5, teams_synced: 2, external_detected: 1 }
      mock_service = Minitest::Mock.new
      mock_service.expect(:sync_all, mock_result)

      GithubSyncService.stub(:new, mock_service) do
        post "/api/developers/sync"
      end

      assert_response :success
      json = JSON.parse(response.body)
      assert json["success"]
      assert_equal 5, json["members_synced"]
      assert_equal 2, json["teams_synced"]
      assert_equal 1, json["external_detected"]

      mock_service.verify
    end

    test "sync returns 403 for non-owner" do
      sign_in_as(role: :developer)

      post "/api/developers/sync"

      assert_response :forbidden
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
