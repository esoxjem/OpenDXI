# frozen_string_literal: true

# Hourly job to refresh GitHub metrics for current and previous sprint.
class RefreshGithubDataJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: -> { "github_refresh" }

  def perform
    Rails.logger.info "[RefreshGithubDataJob] Starting hourly refresh"

    results = Sprint.available_sprints(limit: 2).map do |sprint_info|
      refresh_sprint(sprint_info)
    end

    succeeded = results.count(:success)
    failed = results.count(:failed)

    status = if failed.zero?
               "ok"
             elsif succeeded.zero?
               "failed"
             else
               "partial"
             end

    persist_status(status: status, sprints_succeeded: succeeded, sprints_failed: failed)
    Rails.logger.info "[RefreshGithubDataJob] Completed: #{succeeded} succeeded, #{failed} failed"
  rescue GithubService::GitHubApiError, Faraday::Error => e
    persist_status(status: "failed", error: e.message)
    Rails.logger.error "[RefreshGithubDataJob] Failed: #{e.class} - #{e.message}"
    # Don't re-raise - job completes, next hourly run will retry
  end

  private

  def refresh_sprint(sprint_info)
    start_date = sprint_info[:start_date]
    end_date = sprint_info[:end_date]

    Rails.logger.info "[RefreshGithubDataJob] Refreshing #{start_date} to #{end_date}"
    SprintLoader.new.load(start_date, end_date, force: true)
    :success
  rescue GithubService::GitHubApiError, Faraday::Error => e
    Rails.logger.warn "[RefreshGithubDataJob] Sprint #{start_date} failed: #{e.message}"
    :failed
  end

  def persist_status(status:, error: nil, sprints_succeeded: nil, sprints_failed: nil)
    JobStatus.upsert(
      {
        name: "github_refresh",
        status: status,
        ran_at: Time.current,
        error: sanitize_error_message(error),
        sprints_succeeded: sprints_succeeded,
        sprints_failed: sprints_failed,
        created_at: Time.current,
        updated_at: Time.current
      },
      unique_by: :name
    )
  end

  def sanitize_error_message(error)
    return nil if error.nil?

    case error
    when /rate limit/i then "GitHub API rate limit exceeded"
    when /authentication|token/i then "GitHub authentication issue"
    when /connection|timeout/i then "Connection issue with external service"
    else "An error occurred during data refresh"
    end
  end
end
