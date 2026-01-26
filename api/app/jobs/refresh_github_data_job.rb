# frozen_string_literal: true

# Refreshes GitHub metrics for current and previous sprint.
#
# Scheduled to run every hour via Solid Queue recurring tasks.
#
# Error Handling:
# - GitHub API errors are logged and the job completes gracefully
# - Next hourly run will retry the refresh
# - Partial success is acceptable (if one sprint fails, others may succeed)
class RefreshGithubDataJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "[RefreshGithubDataJob] Starting hourly refresh"

    Sprint.available_sprints(limit: 2).each do |sprint_info|
      refresh_sprint(sprint_info)
    end

    cache_status(status: "ok")
    Rails.logger.info "[RefreshGithubDataJob] Completed successfully"
  rescue GithubService::GitHubApiError, Faraday::Error => e
    cache_status(status: "failed", error: e.message)
    Rails.logger.error "[RefreshGithubDataJob] Failed: #{e.class} - #{e.message}"
    # Don't re-raise - job completes, next hourly run will retry
  end

  private

  def refresh_sprint(sprint_info)
    start_date = sprint_info[:start_date]
    end_date = sprint_info[:end_date]

    Rails.logger.info "[RefreshGithubDataJob] Refreshing #{start_date} to #{end_date}"
    SprintLoader.new.load(start_date, end_date, force: true)
  rescue GithubService::GitHubApiError, Faraday::Error => e
    Rails.logger.warn "[RefreshGithubDataJob] Sprint #{start_date} failed: #{e.message}"
    # Continue with next sprint
  end

  def cache_status(status:, error: nil)
    Rails.cache.write("github_refresh", {
      at: Time.current.iso8601,
      status: status,
      error: error
    }.compact)
  end
end
