# frozen_string_literal: true

require "test_helper"

class DeveloperTest < ActiveSupport::TestCase
  # ═══════════════════════════════════════════════════════════════════════════
  # Validations
  # ═══════════════════════════════════════════════════════════════════════════

  test "valid developer with all attributes" do
    dev = Developer.new(
      github_id: 999999,
      github_login: "newdev",
      name: "New Dev",
      avatar_url: "https://github.com/newdev.png"
    )
    assert dev.valid?
  end

  test "requires github_id" do
    dev = Developer.new(github_login: "test")
    assert_not dev.valid?
    assert_includes dev.errors[:github_id], "can't be blank"
  end

  test "requires github_login" do
    dev = Developer.new(github_id: 999999)
    assert_not dev.valid?
    assert_includes dev.errors[:github_login], "can't be blank"
  end

  test "github_id must be unique" do
    existing = developers(:alice_dev)
    dev = Developer.new(github_id: existing.github_id, github_login: "different")
    assert_not dev.valid?
    assert_includes dev.errors[:github_id], "has already been taken"
  end

  test "github_login must be unique" do
    existing = developers(:alice_dev)
    dev = Developer.new(github_id: 999999, github_login: existing.github_login)
    assert_not dev.valid?
    assert_includes dev.errors[:github_login], "has already been taken"
  end

  test "source must be org_member or external" do
    dev = Developer.new(github_id: 999999, github_login: "test", source: "invalid")
    assert_not dev.valid?
    assert_includes dev.errors[:source], "is not included in the list"
  end

  test "default source is org_member" do
    dev = Developer.new(github_id: 999999, github_login: "test")
    assert_equal "org_member", dev.source
  end

  test "default visible is true" do
    dev = Developer.new(github_id: 999999, github_login: "test")
    assert dev.visible
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Scopes
  # ═══════════════════════════════════════════════════════════════════════════

  test "visible scope returns only visible developers" do
    visible = Developer.visible
    assert visible.include?(developers(:alice_dev))
    assert visible.include?(developers(:bob_dev))
    assert_not visible.include?(developers(:hidden_dev))
  end

  test "org_members scope returns only org members" do
    org = Developer.org_members
    assert org.include?(developers(:alice_dev))
    assert_not org.include?(developers(:charlie_dev))
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Class Methods
  # ═══════════════════════════════════════════════════════════════════════════

  test "visible_logins returns logins of visible developers" do
    logins = Developer.visible_logins
    assert_includes logins, "alice"
    assert_includes logins, "bob"
    assert_includes logins, "charlie"
    assert_not_includes logins, "hidden-user"
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Associations
  # ═══════════════════════════════════════════════════════════════════════════

  test "has many teams through team_memberships" do
    alice = developers(:alice_dev)
    assert_equal 2, alice.teams.count
    assert_includes alice.teams, teams(:backend)
    assert_includes alice.teams, teams(:frontend_team)
  end

  test "destroying developer destroys team memberships" do
    alice = developers(:alice_dev)
    membership_count = alice.team_memberships.count
    assert membership_count > 0

    assert_difference "TeamMembership.count", -membership_count do
      alice.destroy!
    end
  end
end
