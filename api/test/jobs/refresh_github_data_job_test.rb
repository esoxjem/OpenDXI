# frozen_string_literal: true

require "test_helper"

class RefreshGithubDataJobTest < ActiveJob::TestCase
  # ═══════════════════════════════════════════════════════════════════════════
  # Setup
  # ═══════════════════════════════════════════════════════════════════════════

  setup do
    # Use memory store for these tests since the job relies on Rails.cache
    # (test.rb uses :null_store by default which discards all writes)
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    Rails.cache.clear
  end

  teardown do
    Rails.cache = @original_cache
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Success Cases
  # ═══════════════════════════════════════════════════════════════════════════

  test "refreshes current and previous sprint with force true" do
    # Track what SprintLoader receives
    loaded_sprints = []

    # Create a custom fetcher that records calls
    recording_fetcher = Object.new
    recording_fetcher.define_singleton_method(:fetch_sprint_data) do |start_date, end_date|
      loaded_sprints << { start_date: start_date.to_s, end_date: end_date.to_s }
      { "developers" => [], "summary" => {} }
    end

    # Temporarily replace GithubService with our recording fetcher
    original_fetcher = SprintLoader.instance_method(:initialize).bind(SprintLoader.allocate).call.instance_variable_get(:@fetcher)

    SprintLoader.define_method(:initialize) do |fetcher: recording_fetcher|
      @fetcher = fetcher
    end

    begin
      RefreshGithubDataJob.perform_now

      # Should have loaded 2 sprints (current + previous)
      assert_equal 2, loaded_sprints.size

      # Check cache status
      status = Rails.cache.read("github_refresh")
      assert_equal "ok", status[:status]
      assert_not_nil status[:at]
    ensure
      # Restore original behavior
      SprintLoader.define_method(:initialize) do |fetcher: GithubService|
        @fetcher = fetcher
      end
    end
  end

  test "records failure status when Sprint.available_sprints raises API error" do
    # The outer rescue catches errors from available_sprints, not individual sprint refreshes
    # (individual failures are logged and skipped in refresh_sprint)
    original_method = Sprint.method(:available_sprints)

    Sprint.define_singleton_method(:available_sprints) do |limit: 6|
      raise GithubService::GitHubApiError, "Rate limited"
    end

    begin
      RefreshGithubDataJob.perform_now

      status = Rails.cache.read("github_refresh")
      assert_equal "failed", status[:status]
      assert_equal "Rate limited", status[:error]
    ensure
      Sprint.define_singleton_method(:available_sprints, original_method)
    end
  end

  test "continues to next sprint when one fails" do
    call_count = 0
    loaded_sprints = []

    # Create a fetcher that fails on first call but succeeds on second
    flaky_fetcher = Object.new
    flaky_fetcher.define_singleton_method(:fetch_sprint_data) do |start_date, end_date|
      call_count += 1
      if call_count == 1
        raise GithubService::GitHubApiError, "Failed for first sprint"
      end
      loaded_sprints << { start_date: start_date.to_s, end_date: end_date.to_s }
      { "developers" => [], "summary" => {} }
    end

    SprintLoader.define_method(:initialize) do |fetcher: flaky_fetcher|
      @fetcher = fetcher
    end

    begin
      RefreshGithubDataJob.perform_now

      # Should have attempted both sprints (2 calls)
      assert_equal 2, call_count

      # Second sprint should have succeeded
      assert_equal 1, loaded_sprints.size

      # Job should still complete successfully overall
      status = Rails.cache.read("github_refresh")
      assert_equal "ok", status[:status]
    ensure
      SprintLoader.define_method(:initialize) do |fetcher: GithubService|
        @fetcher = fetcher
      end
    end
  end

  test "handles Faraday connection errors gracefully" do
    # Create a fetcher that raises Faraday errors
    network_error_fetcher = Object.new
    network_error_fetcher.define_singleton_method(:fetch_sprint_data) do |_start, _end|
      raise Faraday::ConnectionFailed, "Connection refused"
    end

    SprintLoader.define_method(:initialize) do |fetcher: network_error_fetcher|
      @fetcher = fetcher
    end

    begin
      RefreshGithubDataJob.perform_now

      # Job should complete (not raise) and log the error
      status = Rails.cache.read("github_refresh")
      # All sprints failed individually, but job completed with ok status
      # because individual failures don't bubble up
      assert_equal "ok", status[:status]
    ensure
      SprintLoader.define_method(:initialize) do |fetcher: GithubService|
        @fetcher = fetcher
      end
    end
  end

  test "cache status does not include error key on success" do
    success_fetcher = Object.new
    success_fetcher.define_singleton_method(:fetch_sprint_data) do |_start, _end|
      { "developers" => [], "summary" => {} }
    end

    SprintLoader.define_method(:initialize) do |fetcher: success_fetcher|
      @fetcher = fetcher
    end

    begin
      RefreshGithubDataJob.perform_now

      status = Rails.cache.read("github_refresh")
      assert_equal "ok", status[:status]
      assert_not status.key?(:error)
    ensure
      SprintLoader.define_method(:initialize) do |fetcher: GithubService|
        @fetcher = fetcher
      end
    end
  end

  test "handles empty sprints list gracefully" do
    # Temporarily override available_sprints to return empty
    original_method = Sprint.method(:available_sprints)

    Sprint.define_singleton_method(:available_sprints) do |limit: 6|
      []
    end

    begin
      RefreshGithubDataJob.perform_now

      status = Rails.cache.read("github_refresh")
      assert_equal "ok", status[:status]
    ensure
      Sprint.define_singleton_method(:available_sprints, original_method)
    end
  end
end
