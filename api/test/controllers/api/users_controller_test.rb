# frozen_string_literal: true

require "test_helper"

module Api
  class UsersControllerTest < ActionDispatch::IntegrationTest
    # ═══════════════════════════════════════════════════════════════════════════
    # GET /api/users
    # ═══════════════════════════════════════════════════════════════════════════

    test "index returns all users for owner" do
      sign_in_as(role: :owner)

      get "/api/users"

      assert_response :success
      json = JSON.parse(response.body)
      assert json["users"].is_a?(Array)
      # Should include at least the signed-in user
      assert json["users"].any? { |u| u["role"].present? }
    end

    test "index returns 403 for developer" do
      sign_in_as(role: :developer)

      get "/api/users"

      assert_response :forbidden
    end

    test "index returns 401 for unauthenticated user" do
      get "/api/users"

      assert_response :unauthorized
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # PATCH /api/users/:id
    # ═══════════════════════════════════════════════════════════════════════════

    test "update changes user role for owner" do
      owner = sign_in_as(role: :owner)
      target_user = User.create!(
        github_id: SecureRandom.random_number(1_000_000),
        login: "target-#{SecureRandom.hex(4)}",
        name: "Target User",
        avatar_url: "https://example.com/avatar.png",
        role: :developer
      )

      patch "/api/users/#{target_user.id}", params: { role: "owner" }

      assert_response :success
      json = JSON.parse(response.body)
      assert json["success"]
      assert_equal "owner", json["user"]["role"]

      target_user.reload
      assert target_user.owner?
    end

    test "update returns 403 for developer" do
      sign_in_as(role: :developer)
      target_user = users(:alice)

      patch "/api/users/#{target_user.id}", params: { role: "owner" }

      assert_response :forbidden
    end

    test "update returns 422 for invalid role" do
      sign_in_as(role: :owner)
      target_user = users(:alice)

      patch "/api/users/#{target_user.id}", params: { role: "superadmin" }

      assert_response :unprocessable_entity
      json = JSON.parse(response.body)
      assert_equal "invalid_role", json["error"]
    end

    test "update returns 404 for non-existent user" do
      sign_in_as(role: :owner)

      patch "/api/users/999999", params: { role: "owner" }

      assert_response :not_found
      json = JSON.parse(response.body)
      assert_equal "not_found", json["error"]
    end

    test "update allows owner to demote themselves" do
      owner = sign_in_as(role: :owner)

      patch "/api/users/#{owner.id}", params: { role: "developer" }

      assert_response :success
      owner.reload
      assert owner.developer?
    end
  end
end
