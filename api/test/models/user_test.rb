# frozen_string_literal: true

require "test_helper"

class UserTest < ActiveSupport::TestCase
  # ═══════════════════════════════════════════════════════════════════════════
  # Validations
  # ═══════════════════════════════════════════════════════════════════════════

  test "valid user with all attributes" do
    user = User.new(
      github_id: 999999,
      login: "newuser",
      name: "New User",
      avatar_url: "https://github.com/newuser.png"
    )
    assert user.valid?
  end

  test "requires github_id" do
    user = User.new(login: "test", avatar_url: "https://example.com/avatar.png")
    assert_not user.valid?
    assert_includes user.errors[:github_id], "can't be blank"
  end

  test "requires login" do
    user = User.new(github_id: 123, avatar_url: "https://example.com/avatar.png")
    assert_not user.valid?
    assert_includes user.errors[:login], "can't be blank"
  end

  test "github_id must be unique" do
    existing = users(:alice)
    user = User.new(github_id: existing.github_id, login: "different", avatar_url: "https://example.com/avatar.png")
    assert_not user.valid?
    assert_includes user.errors[:github_id], "has already been taken"
  end

  test "login must be unique" do
    existing = users(:alice)
    user = User.new(github_id: 999999, login: existing.login, avatar_url: "https://example.com/avatar.png")
    assert_not user.valid?
    assert_includes user.errors[:login], "has already been taken"
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Role Enum
  # ═══════════════════════════════════════════════════════════════════════════

  test "default role is developer" do
    user = User.new(github_id: 999999, login: "test", avatar_url: "https://example.com/avatar.png")
    assert_equal "developer", user.role
    assert user.developer?
    assert_not user.owner?
  end

  test "can set role to owner" do
    user = User.new(github_id: 999999, login: "test", avatar_url: "https://example.com/avatar.png", role: :owner)
    assert_equal "owner", user.role
    assert user.owner?
    assert_not user.developer?
  end

  test "role enum values are correct" do
    assert_equal 0, User.roles["developer"]
    assert_equal 1, User.roles["owner"]
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Helper Methods
  # ═══════════════════════════════════════════════════════════════════════════

  test "default_avatar_url generates identicon URL" do
    assert_equal "https://github.com/identicons/testuser.png", User.default_avatar_url("testuser")
  end
end
