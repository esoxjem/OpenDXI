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
  # find_or_create_from_github
  # ═══════════════════════════════════════════════════════════════════════════

  test "creates new user from auth hash" do
    auth_hash = {
      "uid" => 888888,
      "info" => {
        "nickname" => "newdev",
        "name" => "New Developer",
        "image" => "https://github.com/newdev.png"
      }
    }

    assert_difference "User.count", 1 do
      user = User.find_or_create_from_github(auth_hash)
      assert_equal 888888, user.github_id
      assert_equal "newdev", user.login
      assert_equal "New Developer", user.name
      assert_equal "https://github.com/newdev.png", user.avatar_url
      assert user.developer?
    end
  end

  test "updates existing user from auth hash" do
    existing = users(:alice)
    auth_hash = {
      "uid" => existing.github_id,
      "info" => {
        "nickname" => "alice",
        "name" => "Alice Updated Name",
        "image" => "https://github.com/alice-new.png"
      }
    }

    assert_no_difference "User.count" do
      user = User.find_or_create_from_github(auth_hash)
      assert_equal existing.id, user.id
      assert_equal "Alice Updated Name", user.name
      assert_equal "https://github.com/alice-new.png", user.avatar_url
      # Role should not change for existing users
      assert user.developer?
    end
  end

  test "uses default avatar url when image is nil" do
    auth_hash = {
      "uid" => 777777,
      "info" => {
        "nickname" => "noavatar",
        "name" => "No Avatar User",
        "image" => nil
      }
    }

    user = User.find_or_create_from_github(auth_hash)
    assert_equal "https://github.com/identicons/noavatar.png", user.avatar_url
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Owner Bootstrap
  # ═══════════════════════════════════════════════════════════════════════════

  test "bootstraps owner when login matches OWNER_GITHUB_USERNAME" do
    ENV["OWNER_GITHUB_USERNAME"] = "bootstrapowner"

    auth_hash = {
      "uid" => 666666,
      "info" => {
        "nickname" => "bootstrapowner",
        "name" => "Bootstrap Owner",
        "image" => "https://github.com/bootstrapowner.png"
      }
    }

    user = User.find_or_create_from_github(auth_hash)
    assert user.owner?, "User should be bootstrapped as owner"
  ensure
    ENV.delete("OWNER_GITHUB_USERNAME")
  end

  test "owner bootstrap is case insensitive" do
    ENV["OWNER_GITHUB_USERNAME"] = "BootstrapOwner"

    auth_hash = {
      "uid" => 555555,
      "info" => {
        "nickname" => "bootstrapowner",
        "name" => "Bootstrap Owner",
        "image" => "https://github.com/bootstrapowner.png"
      }
    }

    user = User.find_or_create_from_github(auth_hash)
    assert user.owner?, "Owner bootstrap should be case insensitive"
  ensure
    ENV.delete("OWNER_GITHUB_USERNAME")
  end

  test "does not promote existing user to owner on subsequent login" do
    existing = users(:alice)
    ENV["OWNER_GITHUB_USERNAME"] = existing.login

    auth_hash = {
      "uid" => existing.github_id,
      "info" => {
        "nickname" => existing.login,
        "name" => existing.name,
        "image" => existing.avatar_url
      }
    }

    user = User.find_or_create_from_github(auth_hash)
    assert user.developer?, "Existing user should not be promoted to owner"
  ensure
    ENV.delete("OWNER_GITHUB_USERNAME")
  end

  test "owner_bootstrap_login? returns false when env var not set" do
    ENV.delete("OWNER_GITHUB_USERNAME")
    assert_not User.owner_bootstrap_login?("anyuser")
  end

  test "owner_bootstrap_login? handles nil login gracefully" do
    ENV["OWNER_GITHUB_USERNAME"] = "someuser"
    assert_not User.owner_bootstrap_login?(nil)
  ensure
    ENV.delete("OWNER_GITHUB_USERNAME")
  end
end
