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
    users = User.order(:login).select(:id, :github_id, :login, :name, :avatar_url, :role, :last_login_at, :created_at)
    render json: { users: users }
  end

  # POST /api/users
  # Creates a new user by GitHub handle (fetches details from GitHub API)
  def create
    login = params[:login]&.strip
    if login.blank?
      render json: { error: "invalid_request", detail: "GitHub login is required" }, status: :unprocessable_entity
      return
    end

    # Fetch user details from GitHub
    github_user = GithubService.fetch_user_by_login(login)

    if github_user.nil?
      render json: { error: "not_found", detail: "GitHub user '#{login}' not found" }, status: :not_found
      return
    end

    # Check if user already exists
    if User.exists?(github_id: github_user[:github_id])
      render json: { error: "conflict", detail: "User '#{login}' already exists" }, status: :conflict
      return
    end

    user = User.create!(
      github_id: github_user[:github_id],
      login: github_user[:login],
      name: github_user[:name],
      avatar_url: github_user[:avatar_url] || User.default_avatar_url(github_user[:login]),
      role: :developer
    )

    Rails.logger.info "[UserManagement] User '#{user.login}' (github_id: #{user.github_id}) created by '#{current_user.login}'"
    render json: { user: user.slice(:id, :github_id, :login, :name, :avatar_url, :role, :last_login_at, :created_at) }, status: :created

  rescue ActiveRecord::RecordNotUnique
    render json: { error: "conflict", detail: "User already exists" }, status: :conflict
  rescue GithubService::GitHubApiError => e
    render json: { error: "github_error", detail: e.message }, status: :bad_gateway
  end

  # DELETE /api/users/:id
  # Removes a user from the system
  def destroy
    user = User.find(params[:id])

    if user.id == current_user.id
      render json: { error: "invalid_operation", detail: "Cannot delete yourself" }, status: :unprocessable_entity
      return
    end

    # Prevent deleting the last owner
    if user.owner? && User.where(role: :owner).count == 1
      render json: { error: "invalid_operation", detail: "Cannot delete the last owner" }, status: :unprocessable_entity
      return
    end

    Rails.logger.info "[UserManagement] User '#{user.login}' (github_id: #{user.github_id}) deleted by '#{current_user.login}'"
    user.destroy!

    render json: { success: true }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "not_found", detail: "User not found" }, status: :not_found
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
