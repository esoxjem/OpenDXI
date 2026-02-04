# frozen_string_literal: true

# Developer API endpoints
#
# Provides both sprint-derived developer lists (for dashboard)
# and managed developer records (for Settings page).
module Api
  class DevelopersController < BaseController
    before_action :require_owner!, only: [:managed, :update, :sync]

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

    # GET /api/developers/managed
    #
    # Returns all Developer records with team assignments.
    # Used by the Settings page for developer management.
    # Owner-only.
    def managed
      developers = Developer.includes(:teams).order(:github_login)

      render json: {
        developers: developers.map { |d| serialize_developer(d) }
      }
    end

    # PATCH /api/developers/:id
    #
    # Toggle developer visibility on the dashboard.
    # Owner-only.
    def update
      developer = Developer.find(params[:id])
      developer.update!(visible: developer_params[:visible])

      render json: { developer: serialize_developer(developer) }
    end

    # POST /api/developers/sync
    #
    # Triggers a full GitHub sync: org members, teams, and external contributors.
    # Owner-only.
    def sync
      result = GithubSyncService.new.sync_all

      render json: {
        success: true,
        members_synced: result[:members_synced],
        teams_synced: result[:teams_synced],
        external_detected: result[:external_detected]
      }
    end

    # GET /api/developers/:name/history
    #
    # Returns historical metrics for a specific developer across multiple sprints.
    # Also includes team averages for comparison.
    # Sprints are ordered chronologically (oldest first) for proper trend display.
    # Supports count query param (default: 6, max: 12).
    def history
      developer_name = URI.decode_www_form_component(params[:name])
      count = (params[:count] || 6).to_i.clamp(1, 12)

      # Order ascending so trends show oldest→newest (left→right on charts)
      sprints = Sprint.order(start_date: :desc).limit(count).reverse

      # Verify developer exists in at least one sprint
      found_in_any = sprints.any? { |s| s.find_developer(developer_name) }
      raise ActiveRecord::RecordNotFound, "Developer '#{developer_name}' not found" unless found_in_any

      render json: DeveloperHistorySerializer.new(developer_name, sprints).as_json
    end

    private

    def developer_params
      params.require(:developer).permit(:visible)
    end

    def serialize_developer(dev)
      {
        id: dev.id,
        github_id: dev.github_id,
        github_login: dev.github_login,
        name: dev.name,
        avatar_url: dev.avatar_url,
        visible: dev.visible,
        source: dev.source,
        teams: dev.teams.map { |t| { id: t.id, name: t.name, slug: t.slug } }
      }
    end
  end
end
