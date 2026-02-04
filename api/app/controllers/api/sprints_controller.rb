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
    # Supports ?team=slug to filter by team membership.
    #
    # HTTP Caching:
    # - Returns 304 Not Modified if client ETag matches (bandwidth optimization)
    # - Always returns 200 OK when force_refresh=true (bypass cache)
    # - Sets cache headers for browser and CDN caching
    # - ETag incorporates filter params (different filters = different ETags)
    def metrics
      start_date = Date.parse(params[:start_date])
      end_date = Date.parse(params[:end_date])
      force_refresh = params[:force_refresh] == "true"

      sprint = Sprint.find_or_fetch!(start_date, end_date, force: force_refresh)
      filters = resolve_filters

      # Set cache headers for browser/CDN
      response.cache_control[:public] = true
      response.cache_control[:max_age] = 5.minutes.to_i

      # If force_refresh, always return full response (bypass ETag check)
      if force_refresh
        return render json: MetricsResponseSerializer.new(sprint, **filters).as_json
      end

      # Generate ETag based on content hash + filter params
      etag = generate_filtered_cache_key(sprint, filters)

      # Check if client has matching ETag in If-None-Match header
      if request.headers["If-None-Match"] == "\"#{etag}\""
        # Client has matching ETag - return 304 Not Modified
        return head :not_modified
      end

      # Return full response with ETag header
      response.set_header("ETag", "\"#{etag}\"")
      render json: MetricsResponseSerializer.new(sprint, **filters).as_json
    end

    # GET /api/sprints/history
    #
    # Returns historical DXI scores across multiple sprints for trend analysis.
    # Sprints are ordered chronologically (oldest first) for proper trend display.
    # Supports count query param (default: 6, max: 12).
    # Supports ?team=slug to filter by team membership.
    def history
      count = (params[:count] || 6).to_i.clamp(1, 12)
      # Order ascending so trends show oldest→newest (left→right on charts)
      sprints = Sprint.order(start_date: :desc).limit(count).reverse
      filters = resolve_filters.except(:team_name)

      render json: {
        sprints: sprints.map { |s| SprintHistorySerializer.new(s, **filters).as_json }
      }
    end

    private

    # Resolves visibility and team filter params into serializer kwargs.
    # Returns empty hash when no filters are active (backwards compatible).
    def resolve_filters
      filters = {}

      # Always apply visibility filtering when Developer records exist
      if Developer.exists?
        filters[:visible_logins] = Developer.visible_logins
      end

      # Apply team filter if ?team=slug is present
      if params[:team].present?
        team = Team.find_by(slug: params[:team])
        if team
          filters[:team_logins] = team.developers.visible.pluck(:github_login)
          filters[:team_name] = team.name
        end
      end

      filters
    end

    # Generates an ETag that accounts for filter params.
    # Different filters produce different ETags so cached responses
    # don't serve stale filtered/unfiltered data.
    def generate_filtered_cache_key(sprint, filters)
      base_key = sprint.generate_cache_key
      return base_key if filters.empty?

      filter_key = Digest::SHA256.hexdigest(filters.except(:team_name).to_json)
      "#{base_key}-#{filter_key[0..7]}"
    end

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
