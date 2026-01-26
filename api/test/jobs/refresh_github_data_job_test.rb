# frozen_string_literal: true

require "test_helper"

class RefreshGithubDataJobTest < ActiveJob::TestCase
  class MockFetcher
    attr_reader :calls

    def initialize(responses: nil, error: nil)
      @responses = responses || [{ "developers" => [], "summary" => {} }]
      @error = error
      @calls = []
      @call_index = 0
    end

    def fetch_sprint_data(start_date, end_date)
      @calls << { start_date: start_date.to_s, end_date: end_date.to_s }
      raise @error if @error
      response = @responses[@call_index] || @responses.last
      @call_index += 1
      response
    end
  end

  class FailingThenSucceedingFetcher
    attr_reader :calls

    def initialize
      @calls = []
      @call_count = 0
    end

    def fetch_sprint_data(start_date, end_date)
      @call_count += 1
      if @call_count == 1
        raise GithubService::GitHubApiError, "Failed for first sprint"
      end
      @calls << { start_date: start_date.to_s, end_date: end_date.to_s }
      { "developers" => [], "summary" => {} }
    end

    def total_attempts
      @call_count
    end
  end

  setup do
    # Clean up any existing job status records
    JobStatus.delete_all
  end

  test "refreshes current and previous sprint with force true" do
    mock_fetcher = MockFetcher.new

    with_mock_fetcher(mock_fetcher) do
      RefreshGithubDataJob.perform_now
    end

    assert_equal 2, mock_fetcher.calls.size

    job_status = JobStatus.find_by(name: "github_refresh")
    assert_not_nil job_status
    assert_equal "ok", job_status.status
    assert_equal 2, job_status.sprints_succeeded
    assert_equal 0, job_status.sprints_failed
    assert_not_nil job_status.ran_at
  end

  test "records failure status when Sprint.available_sprints raises API error" do
    with_stubbed_available_sprints(-> { raise GithubService::GitHubApiError, "Rate limited" }) do
      RefreshGithubDataJob.perform_now

      job_status = JobStatus.find_by(name: "github_refresh")
      assert_not_nil job_status
      assert_equal "failed", job_status.status
      assert_equal "GitHub API rate limit exceeded", job_status.error
    end
  end

  test "continues to next sprint when one fails and reports partial status" do
    mock_fetcher = FailingThenSucceedingFetcher.new

    with_mock_fetcher(mock_fetcher) do
      RefreshGithubDataJob.perform_now
    end

    assert_equal 2, mock_fetcher.total_attempts
    assert_equal 1, mock_fetcher.calls.size

    job_status = JobStatus.find_by(name: "github_refresh")
    assert_not_nil job_status
    assert_equal "partial", job_status.status
    assert_equal 1, job_status.sprints_succeeded
    assert_equal 1, job_status.sprints_failed
  end

  test "handles Faraday connection errors gracefully and reports failed status" do
    mock_fetcher = MockFetcher.new(error: Faraday::ConnectionFailed.new("Connection refused"))

    with_mock_fetcher(mock_fetcher) do
      RefreshGithubDataJob.perform_now
    end

    job_status = JobStatus.find_by(name: "github_refresh")
    assert_not_nil job_status
    # All sprints failed, so status is "failed" not "ok"
    assert_equal "failed", job_status.status
    assert_equal 0, job_status.sprints_succeeded
    assert_equal 2, job_status.sprints_failed
  end

  test "job status does not include error on success" do
    mock_fetcher = MockFetcher.new

    with_mock_fetcher(mock_fetcher) do
      RefreshGithubDataJob.perform_now
    end

    job_status = JobStatus.find_by(name: "github_refresh")
    assert_not_nil job_status
    assert_equal "ok", job_status.status
    assert_nil job_status.error
  end

  test "handles empty sprints list gracefully" do
    with_stubbed_available_sprints(-> { [] }) do
      RefreshGithubDataJob.perform_now

      job_status = JobStatus.find_by(name: "github_refresh")
      assert_not_nil job_status
      assert_equal "ok", job_status.status
    end
  end

  private

  def with_mock_fetcher(mock_fetcher)
    original_new = SprintLoader.method(:new)
    SprintLoader.define_singleton_method(:new) do |fetcher: nil|
      original_new.call(fetcher: mock_fetcher)
    end
    yield
  ensure
    SprintLoader.define_singleton_method(:new, original_new)
  end

  def with_stubbed_available_sprints(callable)
    original_method = Sprint.method(:available_sprints)
    Sprint.define_singleton_method(:available_sprints) do |limit: 6|
      callable.call
    end
    yield
  ensure
    Sprint.define_singleton_method(:available_sprints, original_method)
  end
end
