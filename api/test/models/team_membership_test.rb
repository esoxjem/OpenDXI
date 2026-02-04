# frozen_string_literal: true

require "test_helper"

class TeamMembershipTest < ActiveSupport::TestCase
  # ═══════════════════════════════════════════════════════════════════════════
  # Validations
  # ═══════════════════════════════════════════════════════════════════════════

  test "valid team membership" do
    membership = TeamMembership.new(
      developer: developers(:charlie_dev),
      team: teams(:backend)
    )
    assert membership.valid?
  end

  test "developer_id must be unique within team" do
    existing = team_memberships(:alice_backend)
    duplicate = TeamMembership.new(
      developer: existing.developer,
      team: existing.team
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:developer_id], "has already been taken"
  end

  test "same developer can be in different teams" do
    alice = developers(:alice_dev)
    # alice is already in backend and frontend_team via fixtures
    assert_equal 2, alice.team_memberships.count
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Associations
  # ═══════════════════════════════════════════════════════════════════════════

  test "belongs to developer" do
    membership = team_memberships(:alice_backend)
    assert_equal developers(:alice_dev), membership.developer
  end

  test "belongs to team" do
    membership = team_memberships(:alice_backend)
    assert_equal teams(:backend), membership.team
  end
end
