# frozen_string_literal: true

module Api
  class DevelopersController < BaseController
    # GET /api/developers
    #
    # Returns a list of unique developer names from recent sprints.
    # Supports optional sprint_count parameter (default: 6, max: 12).
    def index
      count = (params[:sprint_count] || 6).to_i.clamp(1, 12)
      sprints = Sprint.order(start_date: :desc).limit(count)

      developers = sprints.flat_map(&:developers)
                          .map { |d| d["developer"] }
                          .compact
                          .uniq
                          .sort

      render json: { developers: developers }
    end

    # GET /api/developers/:name/history
    #
    # Returns historical metrics for a specific developer across multiple sprints.
    # Also includes team averages for comparison.
    # Supports count query param (default: 6, max: 12).
    def history
      developer_name = URI.decode_www_form_component(params[:name])
      count = (params[:count] || 6).to_i.clamp(1, 12)

      sprints = Sprint.order(start_date: :desc).limit(count)

      # Verify developer exists in at least one sprint
      found_in_any = sprints.any? { |s| s.find_developer(developer_name) }
      raise ActiveRecord::RecordNotFound, "Developer '#{developer_name}' not found" unless found_in_any

      render json: DeveloperHistorySerializer.new(developer_name, sprints).as_json
    end
  end
end
