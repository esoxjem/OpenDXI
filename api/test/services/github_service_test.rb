# frozen_string_literal: true

require "test_helper"
require "webmock/minitest"

class GithubServiceTest < ActiveSupport::TestCase
  setup do
    @original_token = ENV["GH_TOKEN"]
    @original_org = Rails.application.config.opendxi.github_org
    ENV["GH_TOKEN"] = "test-token"
    Rails.application.config.opendxi.github_org = "test-org"
  end

  teardown do
    ENV["GH_TOKEN"] = @original_token
    Rails.application.config.opendxi.github_org = @original_org
    WebMock.reset!
  end

  test "raises GitHubApiError when GH_TOKEN not set" do
    ENV.delete("GH_TOKEN")

    error = assert_raises(GithubService::GitHubApiError) do
      GithubService.fetch_sprint_data(Date.today - 14, Date.today)
    end

    assert_match(/GH_TOKEN not set/, error.message)
  end

  test "raises AuthenticationError on 401 response" do
    stub_request(:post, "https://api.github.com/graphql")
      .to_return(
        status: 401,
        body: { message: "Bad credentials" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    assert_raises(GithubService::AuthenticationError) do
      GithubService.fetch_sprint_data(Date.today - 14, Date.today)
    end
  end

  test "raises RateLimitExceeded on 429 response" do
    stub_request(:post, "https://api.github.com/graphql")
      .to_return(
        status: 429,
        body: { message: "API rate limit exceeded" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    assert_raises(GithubService::RateLimitExceeded) do
      GithubService.fetch_sprint_data(Date.today - 14, Date.today)
    end
  end

  test "raises RateLimitExceeded on 403 response when rate limit exhausted" do
    stub_request(:post, "https://api.github.com/graphql")
      .to_return(
        status: 403,
        body: { message: "API rate limit exceeded" }.to_json,
        headers: {
          "Content-Type" => "application/json",
          "X-RateLimit-Remaining" => "0"
        }
      )

    error = assert_raises(GithubService::RateLimitExceeded) do
      GithubService.fetch_sprint_data(Date.today - 14, Date.today)
    end

    assert_match(/rate limit exceeded/, error.message)
  end

  test "raises AuthenticationError on 403 response when permission denied" do
    stub_request(:post, "https://api.github.com/graphql")
      .to_return(
        status: 403,
        body: { message: "Resource not accessible by integration" }.to_json,
        headers: {
          "Content-Type" => "application/json",
          "X-RateLimit-Remaining" => "4999"
        }
      )

    error = assert_raises(GithubService::AuthenticationError) do
      GithubService.fetch_sprint_data(Date.today - 14, Date.today)
    end

    assert_match(/permission denied/, error.message)
    assert_match(/repo.*read:org/, error.message)
  end

  test "raises AuthenticationError on 403 response without rate limit headers" do
    stub_request(:post, "https://api.github.com/graphql")
      .to_return(
        status: 403,
        body: { message: "Forbidden" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    error = assert_raises(GithubService::AuthenticationError) do
      GithubService.fetch_sprint_data(Date.today - 14, Date.today)
    end

    assert_match(/permission denied/, error.message)
  end

  test "returns data when no repositories found" do
    stub_request(:post, "https://api.github.com/graphql")
      .to_return(
        status: 200,
        body: {
          data: {
            organization: {
              repositories: {
                pageInfo: { hasNextPage: false, endCursor: nil },
                nodes: []
              }
            }
          }
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = GithubService.fetch_sprint_data(Date.today - 14, Date.today)

    assert_equal [], result["developers"]
    assert_equal 0, result["summary"]["total_commits"]
  end

  test "raises GitHubApiError on GraphQL errors with no data" do
    stub_request(:post, "https://api.github.com/graphql")
      .to_return(
        status: 200,
        body: {
          data: nil,
          errors: [{ message: "Field 'invalid' doesn't exist" }]
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    error = assert_raises(GithubService::GitHubApiError) do
      GithubService.fetch_sprint_data(Date.today - 14, Date.today)
    end

    assert_match(/GraphQL error/, error.message)
  end

  test "handles connection timeout gracefully" do
    stub_request(:post, "https://api.github.com/graphql")
      .to_timeout

    error = assert_raises(GithubService::GitHubApiError) do
      GithubService.fetch_sprint_data(Date.today - 14, Date.today)
    end

    assert_match(/Connection failed/, error.message)
  end

  test "handles unexpected status codes" do
    stub_request(:post, "https://api.github.com/graphql")
      .to_return(
        status: 500,
        body: { message: "Internal Server Error" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    error = assert_raises(GithubService::GitHubApiError) do
      GithubService.fetch_sprint_data(Date.today - 14, Date.today)
    end

    assert_match(/GitHub API error \(500\)/, error.message)
  end
end
