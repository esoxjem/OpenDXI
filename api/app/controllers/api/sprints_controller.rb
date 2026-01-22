# frozen_string_literal: true

module Api
  class SprintsController < BaseController
    # Stricter rate limit for force_refresh which triggers expensive GitHub API calls
    # Disabled in development for easier testing
    rate_limit to: 5, within: 1.hour, by: -> { request.remote_ip },
               only: :metrics,
               if: -> { params[:force_refresh] == "true" && !Rails.env.development? },
               with: -> { force_refresh_rate_limited }

    # GET /api/sprints
    #
    # Returns list of available sprints for the dropdown selector.
    # Matches FastAPI's SprintListResponse format.
    def index
      sprints = Sprint.available_sprints

      render json: {
        sprints: sprints.map { |s| serialize_sprint_item(s) }
      }
    end

    # GET /api/sprints/:start_date/:end_date/metrics
    #
    # Returns full metrics for a specific sprint.
    # Supports force_refresh=true query param to bypass cache.
    def metrics
      start_date = Date.parse(params[:start_date])
      end_date = Date.parse(params[:end_date])
      force_refresh = params[:force_refresh] == "true"

      sprint = Sprint.find_or_fetch!(start_date, end_date, force: force_refresh)

      render json: MetricsResponseSerializer.new(sprint).as_json
    end

    # GET /api/sprints/history
    #
    # Returns historical DXI scores across multiple sprints for trend analysis.
    # Sprints are ordered chronologically (oldest first) for proper trend display.
    # Supports count query param (default: 6, max: 12).
    def history
      count = (params[:count] || 6).to_i.clamp(1, 12)
      # Order ascending so trends show oldest→newest (left→right on charts)
      sprints = Sprint.order(start_date: :desc).limit(count).reverse

      render json: {
        sprints: sprints.map { |s| SprintHistorySerializer.new(s).as_json }
      }
    end

    private

    def force_refresh_rate_limited
      render json: {
        error: "rate_limited",
        detail: "Force refresh is limited to 5 requests per hour. Data is cached and usually doesn't need refreshing."
      }, status: :too_many_requests
    end

    def serialize_sprint_item(sprint)
      {
        label: sprint[:label],
        value: sprint[:value],
        start: sprint[:start_date].to_s,
        end: sprint[:end_date].to_s,
        is_current: sprint[:is_current]
      }
    end
  end
end
