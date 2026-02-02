# frozen_string_literal: true

# User management API for owners
#
# Provides list of all users and role management.
# All actions require owner role.
class Api::UsersController < Api::BaseController
  before_action :require_owner!

  # GET /api/users
  # Returns list of all users for the settings page
  def index
    users = User.order(:login).select(:id, :github_id, :login, :name, :avatar_url, :role, :created_at)
    render json: { users: users }
  end

  # PATCH /api/users/:id
  # Updates a user's role
  def update
    user = User.find(params[:id])

    unless %w[developer owner].include?(params[:role])
      render json: { error: "invalid_role", detail: "Role must be 'developer' or 'owner'" }, status: :unprocessable_entity
      return
    end

    user.update!(role: params[:role])
    render json: { success: true, user: user.slice(:id, :login, :role) }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "not_found", detail: "User not found" }, status: :not_found
  end
end
