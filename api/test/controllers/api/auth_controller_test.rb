# frozen_string_literal: true

require "test_helper"

module Api
  class AuthControllerTest < ActionDispatch::IntegrationTest
    # ═══════════════════════════════════════════════════════════════════════════
    # GET /api/auth/me
    # ═══════════════════════════════════════════════════════════════════════════

    test "me returns authenticated true with user info when logged in" do
      sign_in_as

      get "/api/auth/me"

      assert_response :success
      json = JSON.parse(response.body)

      assert json["authenticated"]
      assert_not_nil json["user"]
      assert_equal "testuser", json["user"]["login"]
      assert_equal "Test User", json["user"]["name"]
      assert_equal "12345", json["user"]["github_id"]
    end

    test "me returns authenticated false with login_url when not logged in" do
      get "/api/auth/me"

      assert_response :unauthorized
      json = JSON.parse(response.body)

      assert_not json["authenticated"]
      assert_equal "/auth/github", json["login_url"]
    end
  end
end
