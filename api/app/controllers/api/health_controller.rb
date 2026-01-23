# frozen_string_literal: true

module Api
  class HealthController < BaseController
    # GET /api/health
    def show
      render json: {
        status: "ok",
        version: "1.0.0",
        timestamp: Time.current.iso8601
      }
    end
  end
end
