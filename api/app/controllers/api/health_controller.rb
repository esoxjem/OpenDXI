# frozen_string_literal: true

module Api
  class HealthController < BaseController
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
      cache_status = Rails.cache.read("github_refresh")
      data_freshness = Sprint.maximum(:updated_at)&.iso8601

      return { last_data_update: data_freshness } if cache_status.nil?

      cache_status.merge(last_data_update: data_freshness)
    end
  end
end
