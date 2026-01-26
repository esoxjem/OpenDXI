# frozen_string_literal: true

module Api
  class HealthController < BaseController
    # Health checks must be public for monitoring, load balancers, and Coolify health probes
    skip_before_action :authenticate!

    # GET /api/health
    def show
      render json: {
        status: "ok",
        version: "1.0.0",
        timestamp: Time.current.iso8601,
        refresh: refresh_status
      }.compact
    end

    private

    def refresh_status
      job_status = JobStatus.find_by(name: "github_refresh")
      data_freshness = Sprint.maximum(:updated_at)&.iso8601

      return { last_data_update: data_freshness } if job_status.nil?

      {
        at: job_status.ran_at&.iso8601,
        status: job_status.status,
        error: job_status.error,
        sprints_succeeded: job_status.sprints_succeeded,
        sprints_failed: job_status.sprints_failed,
        last_data_update: data_freshness
      }.compact
    end
  end
end
