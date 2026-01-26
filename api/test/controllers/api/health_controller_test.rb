# frozen_string_literal: true

require "test_helper"

class Api::HealthControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Authenticate before each test
    sign_in_as

    # Clean up any existing job status records
    JobStatus.delete_all
  end

  test "returns health status with version and timestamp" do
    get "/api/health"

    assert_response :success
    json = JSON.parse(response.body)

    assert_equal "ok", json["status"]
    assert_equal "1.0.0", json["version"]
    assert_not_nil json["timestamp"]
  end

  test "includes refresh status when job status exists" do
    # Create job status record in database
    JobStatus.create!(
      name: "github_refresh",
      status: "ok",
      ran_at: Time.zone.parse("2026-01-26T10:00:00Z")
    )

    # Create a sprint to have a data freshness timestamp
    Sprint.create!(
      start_date: Date.new(2026, 1, 7),
      end_date: Date.new(2026, 1, 20),
      data: { "developers" => [] }
    )

    get "/api/health"

    assert_response :success
    json = JSON.parse(response.body)

    assert_not_nil json["refresh"]
    assert_equal "ok", json["refresh"]["status"]
    assert_equal "2026-01-26T10:00:00Z", json["refresh"]["at"]
    assert_not_nil json["refresh"]["last_data_update"]
  end

  test "includes only data freshness when no refresh has run" do
    # Create a sprint without job status
    Sprint.create!(
      start_date: Date.new(2026, 1, 7),
      end_date: Date.new(2026, 1, 20),
      data: { "developers" => [] }
    )

    get "/api/health"

    assert_response :success
    json = JSON.parse(response.body)

    assert_not_nil json["refresh"]
    assert_not_nil json["refresh"]["last_data_update"]
    assert_nil json["refresh"]["status"]
  end

  test "handles no sprints gracefully" do
    get "/api/health"

    assert_response :success
    json = JSON.parse(response.body)

    # refresh key may have nil values but should be present
    assert json.key?("refresh")
  end
end
