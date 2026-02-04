# frozen_string_literal: true

require "test_helper"

class GithubSyncServiceTest < ActiveSupport::TestCase
  # Simple stub for GithubService dependency injection
  class StubGithub
    attr_accessor :org_members, :org_teams, :team_members_map

    def initialize
      @org_members = []
      @org_teams = []
      @team_members_map = {}
    end

    def fetch_org_members
      @org_members
    end

    def fetch_org_teams
      @org_teams
    end

    def fetch_team_members(team_slug)
      @team_members_map[team_slug] || []
    end
  end

  setup do
    @stub_github = StubGithub.new
    @service = GithubSyncService.new(github: @stub_github)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # sync_org_members
  # ═══════════════════════════════════════════════════════════════════════════

  test "sync_org_members creates new developer records" do
    @stub_github.org_members = [
      { "id" => 300001, "login" => "newdev1", "avatar_url" => "https://github.com/newdev1.png" },
      { "id" => 300002, "login" => "newdev2", "avatar_url" => "https://github.com/newdev2.png" }
    ]

    assert_difference "Developer.count", 2 do
      count = @service.sync_org_members
      assert_equal 2, count
    end

    dev = Developer.find_by(github_id: 300001)
    assert_equal "newdev1", dev.github_login
    assert_equal "org_member", dev.source
    assert dev.visible
  end

  test "sync_org_members updates existing developer records" do
    existing = developers(:alice_dev)
    @stub_github.org_members = [
      { "id" => existing.github_id, "login" => "alice-renamed", "avatar_url" => "https://new-avatar.png" }
    ]

    assert_no_difference "Developer.count" do
      @service.sync_org_members
    end

    existing.reload
    assert_equal "alice-renamed", existing.github_login
    assert_equal "https://new-avatar.png", existing.avatar_url
  end

  test "sync_org_members does not delete existing developers not in API response" do
    @stub_github.org_members = []

    assert_no_difference "Developer.count" do
      @service.sync_org_members
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # sync_teams
  # ═══════════════════════════════════════════════════════════════════════════

  test "sync_teams creates new team records" do
    @stub_github.org_teams = [
      { "id" => 5001, "name" => "New Team", "slug" => "new-team" }
    ]
    @stub_github.team_members_map = {
      "new-team" => [
        { "id" => developers(:alice_dev).github_id, "login" => "alice" }
      ]
    }

    assert_difference "Team.count", 1 do
      count = @service.sync_teams
      assert_equal 1, count
    end

    team = Team.find_by(github_team_id: 5001)
    assert_equal "New Team", team.name
    assert_equal "new-team", team.slug
    assert_equal "github", team.source
    assert team.synced?
    assert_includes team.developers, developers(:alice_dev)
  end

  test "sync_teams updates existing synced teams" do
    backend = teams(:backend)
    @stub_github.org_teams = [
      { "id" => backend.github_team_id, "name" => "Backend Updated", "slug" => "backend" }
    ]
    @stub_github.team_members_map = {
      "backend" => [
        { "id" => developers(:alice_dev).github_id, "login" => "alice" }
      ]
    }

    @service.sync_teams

    backend.reload
    assert_equal "Backend Updated", backend.name
    assert backend.synced?
  end

  test "sync_teams skips membership update for diverged teams" do
    diverged = teams(:diverged_team)
    assert_not diverged.synced?

    @stub_github.org_teams = [
      { "id" => diverged.github_team_id, "name" => "Platform", "slug" => "platform" }
    ]
    # Even though team_members_map has data, it should NOT be used for diverged teams
    @stub_github.team_members_map = {
      "platform" => [
        { "id" => developers(:alice_dev).github_id, "login" => "alice" }
      ]
    }

    original_memberships = diverged.team_memberships.count
    @service.sync_teams

    diverged.reload
    assert_not diverged.synced?
    assert_equal original_memberships, diverged.team_memberships.count
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # sync_external_contributors
  # ═══════════════════════════════════════════════════════════════════════════

  test "sync_external_contributors creates records for unknown sprint developers" do
    Sprint.create!(
      start_date: Date.current - 14,
      end_date: Date.current,
      data: {
        "developers" => [
          { "developer" => "unknown-contributor", "dxi_score" => 50 },
          { "developer" => "alice", "dxi_score" => 80 }
        ],
        "daily_activity" => [],
        "summary" => { "developer_count" => 2 },
        "team_dimension_scores" => {}
      }
    )

    assert_difference "Developer.count", 1 do
      count = @service.sync_external_contributors
      assert_equal 1, count
    end

    external = Developer.find_by(github_login: "unknown-contributor")
    assert_equal "external", external.source
    assert external.visible
  end

  test "sync_external_contributors does not create duplicates" do
    assert_no_difference "Developer.count" do
      @service.sync_external_contributors
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # sync_all
  # ═══════════════════════════════════════════════════════════════════════════

  test "sync_all runs all sync steps and returns summary" do
    @stub_github.org_members = [
      { "id" => 300001, "login" => "new-member", "avatar_url" => "https://github.com/new.png" }
    ]
    @stub_github.org_teams = []

    result = @service.sync_all

    assert_equal 1, result[:members_synced]
    assert_equal 0, result[:teams_synced]
    assert result.key?(:external_detected)
  end
end
