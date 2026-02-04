# frozen_string_literal: true

require "test_helper"

module Api
  class TeamsControllerTest < ActionDispatch::IntegrationTest
    # ═══════════════════════════════════════════════════════════════════════════
    # GET /api/teams (available to all authenticated users)
    # ═══════════════════════════════════════════════════════════════════════════

    test "index returns all teams with member counts" do
      sign_in_as

      get "/api/teams"

      assert_response :success
      json = JSON.parse(response.body)

      assert json.key?("teams")
      teams_data = json["teams"]
      assert_kind_of Array, teams_data

      # Should include all teams from fixtures
      team_names = teams_data.map { |t| t["name"] }
      assert_includes team_names, "Backend"
      assert_includes team_names, "Frontend"
      assert_includes team_names, "Platform"
    end

    test "index returns teams sorted by name" do
      sign_in_as

      get "/api/teams"

      assert_response :success
      json = JSON.parse(response.body)
      names = json["teams"].map { |t| t["name"] }
      assert_equal names.sort, names
    end

    test "index includes developer details for each team" do
      sign_in_as

      get "/api/teams"

      assert_response :success
      json = JSON.parse(response.body)

      backend = json["teams"].find { |t| t["name"] == "Backend" }
      assert backend.key?("developers")
      assert backend.key?("developer_count")
      assert_equal 2, backend["developer_count"]

      # Backend has alice and bob
      dev_logins = backend["developers"].map { |d| d["github_login"] }
      assert_includes dev_logins, "alice"
      assert_includes dev_logins, "bob"
    end

    test "index includes team metadata" do
      sign_in_as

      get "/api/teams"

      assert_response :success
      json = JSON.parse(response.body)

      backend = json["teams"].find { |t| t["name"] == "Backend" }
      assert_equal "backend", backend["slug"]
      assert_equal "github", backend["source"]
      assert_equal true, backend["synced"]
    end

    test "index returns 401 for unauthenticated user" do
      get "/api/teams"

      assert_response :unauthorized
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # GET /api/teams/:id (available to all authenticated users)
    # ═══════════════════════════════════════════════════════════════════════════

    test "show returns a single team with developers" do
      sign_in_as
      team = teams(:backend)

      get "/api/teams/#{team.id}"

      assert_response :success
      json = JSON.parse(response.body)

      assert json.key?("team")
      team_data = json["team"]
      assert_equal "Backend", team_data["name"]
      assert_equal "backend", team_data["slug"]
      assert_equal "github", team_data["source"]
      assert_equal true, team_data["synced"]
      assert_equal 2, team_data["developer_count"]

      dev_logins = team_data["developers"].map { |d| d["github_login"] }
      assert_includes dev_logins, "alice"
      assert_includes dev_logins, "bob"
    end

    test "show returns 404 for non-existent team" do
      sign_in_as

      get "/api/teams/999999"

      assert_response :not_found
      json = JSON.parse(response.body)
      assert_equal "not_found", json["error"]
    end

    test "show returns 401 for unauthenticated user" do
      team = teams(:backend)

      get "/api/teams/#{team.id}"

      assert_response :unauthorized
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # POST /api/teams (owner-only)
    # ═══════════════════════════════════════════════════════════════════════════

    test "create makes a new custom team for owner" do
      sign_in_as(role: :owner)

      assert_difference "Team.count", 1 do
        post "/api/teams", params: {
          team: { name: "New Custom Team" }
        }
      end

      assert_response :created
      json = JSON.parse(response.body)
      team = json["team"]
      assert_equal "New Custom Team", team["name"]
      assert_equal "new-custom-team", team["slug"]
      assert_equal "custom", team["source"]
    end

    test "create assigns developers to team" do
      sign_in_as(role: :owner)
      alice = developers(:alice_dev)
      bob = developers(:bob_dev)

      post "/api/teams", params: {
        team: { name: "Cross-Functional", developer_ids: [alice.id, bob.id] }
      }

      assert_response :created
      json = JSON.parse(response.body)
      assert_equal 2, json["team"]["developer_count"]

      dev_logins = json["team"]["developers"].map { |d| d["github_login"] }
      assert_includes dev_logins, "alice"
      assert_includes dev_logins, "bob"
    end

    test "create returns 422 for missing name" do
      sign_in_as(role: :owner)

      post "/api/teams", params: { team: { name: "" } }

      assert_response :unprocessable_entity
      json = JSON.parse(response.body)
      assert_equal "invalid_request", json["error"]
    end

    test "create returns 422 for duplicate team slug" do
      sign_in_as(role: :owner)

      # "Backend" already exists as a fixture, so its slug "backend" is taken
      post "/api/teams", params: { team: { name: "Backend" } }

      assert_response :unprocessable_entity
      json = JSON.parse(response.body)
      assert_equal "invalid_request", json["error"]
    end

    test "create returns 403 for non-owner" do
      sign_in_as(role: :developer)

      post "/api/teams", params: { team: { name: "Unauthorized Team" } }

      assert_response :forbidden
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # PATCH /api/teams/:id (owner-only)
    # ═══════════════════════════════════════════════════════════════════════════

    test "update changes team name for owner" do
      sign_in_as(role: :owner)
      team = teams(:frontend_team)

      patch "/api/teams/#{team.id}", params: { team: { name: "Frontend Revised" } }

      assert_response :success
      json = JSON.parse(response.body)
      assert_equal "Frontend Revised", json["team"]["name"]

      team.reload
      assert_equal "Frontend Revised", team.name
    end

    test "update changes team members for owner" do
      sign_in_as(role: :owner)
      team = teams(:frontend_team)
      charlie = developers(:charlie_dev)
      bob = developers(:bob_dev)

      patch "/api/teams/#{team.id}", params: {
        team: { developer_ids: [charlie.id, bob.id] }
      }

      assert_response :success
      json = JSON.parse(response.body)
      assert_equal 2, json["team"]["developer_count"]
    end

    test "update marks github team as diverged when changing members" do
      sign_in_as(role: :owner)
      team = teams(:backend)
      assert team.synced?
      assert_equal "github", team.source

      patch "/api/teams/#{team.id}", params: {
        team: { developer_ids: [developers(:alice_dev).id] }
      }

      assert_response :success
      team.reload
      assert_not team.synced?, "GitHub team should be marked as diverged after member edit"
    end

    test "update does not mark custom team as diverged" do
      sign_in_as(role: :owner)
      team = teams(:frontend_team)
      assert_equal "custom", team.source

      patch "/api/teams/#{team.id}", params: {
        team: { developer_ids: [developers(:bob_dev).id] }
      }

      assert_response :success
      team.reload
      assert team.synced?, "Custom team synced flag should remain unchanged"
    end

    test "update returns 403 for non-owner" do
      sign_in_as(role: :developer)
      team = teams(:frontend_team)

      patch "/api/teams/#{team.id}", params: { team: { name: "Hacked" } }

      assert_response :forbidden
    end

    test "update returns 404 for non-existent team" do
      sign_in_as(role: :owner)

      patch "/api/teams/999999", params: { team: { name: "Ghost" } }

      assert_response :not_found
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # DELETE /api/teams/:id (owner-only)
    # ═══════════════════════════════════════════════════════════════════════════

    test "destroy deletes team and memberships for owner" do
      sign_in_as(role: :owner)
      team = teams(:frontend_team)
      membership_count = team.team_memberships.count
      assert membership_count > 0, "Team should have memberships to test cascade"

      assert_difference "Team.count", -1 do
        assert_difference "TeamMembership.count", -membership_count do
          delete "/api/teams/#{team.id}"
        end
      end

      assert_response :success
      json = JSON.parse(response.body)
      assert json["success"]
    end

    test "destroy returns 403 for non-owner" do
      sign_in_as(role: :developer)
      team = teams(:frontend_team)

      delete "/api/teams/#{team.id}"

      assert_response :forbidden
    end

    test "destroy returns 404 for non-existent team" do
      sign_in_as(role: :owner)

      delete "/api/teams/999999"

      assert_response :not_found
    end
  end
end
