# frozen_string_literal: true

# Team management API
#
# GET /api/teams is available to all authenticated users (for dashboard filtering).
# All other actions require owner role.
module Api
  class TeamsController < BaseController
    before_action :require_owner!, except: [:index]

    # GET /api/teams
    #
    # Returns all teams with member counts.
    # Available to all authenticated users.
    def index
      teams = Team.includes(:developers).order(:name)

      render json: {
        teams: teams.map { |t| serialize_team(t) }
      }
    end

    # POST /api/teams
    #
    # Creates a custom team. Owner-only.
    def create
      team = Team.new(
        name: params[:name],
        source: "custom"
      )

      if params[:developer_ids].present?
        team.developer_ids = Array(params[:developer_ids]).map(&:to_i)
      end

      team.save!

      render json: { team: serialize_team(team) }, status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: "invalid_request", detail: e.message }, status: :unprocessable_entity
    rescue ActiveRecord::RecordNotUnique
      render json: { error: "conflict", detail: "A team with that name already exists" }, status: :conflict
    end

    # PATCH /api/teams/:id
    #
    # Updates a team's name and/or members.
    # Editing a GitHub-imported team marks it as diverged (synced: false).
    # Owner-only.
    def update
      team = Team.find(params[:id])

      # Mark GitHub-imported team as diverged when editing membership
      if team.source == "github" && params[:developer_ids].present?
        team.synced = false
      end

      team.name = params[:name] if params[:name].present?

      if params[:developer_ids].present?
        team.developer_ids = Array(params[:developer_ids]).map(&:to_i)
      end

      team.save!

      render json: { team: serialize_team(team) }
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: "invalid_request", detail: e.message }, status: :unprocessable_entity
    end

    # DELETE /api/teams/:id
    #
    # Deletes a team and its memberships. Owner-only.
    def destroy
      team = Team.find(params[:id])
      team.destroy!

      render json: { success: true }
    end

    private

    def serialize_team(team)
      {
        id: team.id,
        name: team.name,
        slug: team.slug,
        source: team.source,
        synced: team.synced,
        developer_count: team.developers.size,
        developers: team.developers.map { |d|
          {
            id: d.id,
            github_login: d.github_login,
            name: d.name,
            avatar_url: d.avatar_url
          }
        }
      }
    end
  end
end
