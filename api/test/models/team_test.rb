# frozen_string_literal: true

require "test_helper"

class TeamTest < ActiveSupport::TestCase
  # ═══════════════════════════════════════════════════════════════════════════
  # Validations
  # ═══════════════════════════════════════════════════════════════════════════

  test "valid team with all attributes" do
    team = Team.new(name: "New Team", slug: "new-team")
    assert team.valid?
  end

  test "requires name" do
    team = Team.new(slug: "test")
    assert_not team.valid?
    assert_includes team.errors[:name], "can't be blank"
  end

  test "rejects name longer than 100 characters" do
    team = Team.new(name: "a" * 101)
    assert_not team.valid?
    assert_includes team.errors[:name], "is too long (maximum is 100 characters)"
  end

  test "accepts name of exactly 100 characters" do
    team = Team.new(name: "a" * 100)
    team.valid?
    assert_not_includes team.errors[:name], "is too long (maximum is 100 characters)"
  end

  test "requires slug" do
    team = Team.new(name: "Test")
    # slug is auto-generated, so creating without explicit slug should still be valid
    assert team.valid?
    assert_equal "test", team.slug
  end

  test "slug must be unique" do
    existing = teams(:backend)
    team = Team.new(name: "Another", slug: existing.slug)
    assert_not team.valid?
    assert_includes team.errors[:slug], "has already been taken"
  end

  test "source must be github or custom" do
    team = Team.new(name: "Test", source: "invalid")
    assert_not team.valid?
    assert_includes team.errors[:source], "is not included in the list"
  end

  test "default source is custom" do
    team = Team.new(name: "Test")
    assert_equal "custom", team.source
  end

  test "default synced is true" do
    team = Team.new(name: "Test")
    assert team.synced
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Slug Generation
  # ═══════════════════════════════════════════════════════════════════════════

  test "auto-generates slug from name on create" do
    team = Team.new(name: "My Great Team")
    team.valid?
    assert_equal "my-great-team", team.slug
  end

  test "does not overwrite explicit slug" do
    team = Team.new(name: "My Team", slug: "custom-slug")
    team.valid?
    assert_equal "custom-slug", team.slug
  end

  test "handles special characters in name for slug" do
    team = Team.new(name: "Team A & B")
    team.valid?
    assert_equal "team-a-b", team.slug
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Scopes
  # ═══════════════════════════════════════════════════════════════════════════

  test "github_teams scope returns only github-sourced teams" do
    github = Team.github_teams
    assert github.include?(teams(:backend))
    assert_not github.include?(teams(:frontend_team))
  end

  test "custom_teams scope returns only custom teams" do
    custom = Team.custom_teams
    assert custom.include?(teams(:frontend_team))
    assert_not custom.include?(teams(:backend))
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Associations
  # ═══════════════════════════════════════════════════════════════════════════

  test "has many developers through team_memberships" do
    backend = teams(:backend)
    assert_equal 2, backend.developers.count
    assert_includes backend.developers, developers(:alice_dev)
    assert_includes backend.developers, developers(:bob_dev)
  end

  test "destroying team destroys team memberships" do
    backend = teams(:backend)
    membership_count = backend.team_memberships.count
    assert membership_count > 0

    assert_difference "TeamMembership.count", -membership_count do
      backend.destroy!
    end
  end
end
