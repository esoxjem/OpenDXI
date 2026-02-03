# frozen_string_literal: true

class SessionsController < ApplicationController
  def create
    auth = request.env["omniauth.auth"]
    github_id = auth["uid"]
    login = auth["info"]["nickname"]

    # Try to find existing user by github_id
    user = User.find_by(github_id: github_id)

    if user
      # Existing user: update details (handle/avatar may have changed) and record login
      user.update!(
        login: login,
        name: auth["info"]["name"],
        avatar_url: auth["info"]["image"] || User.default_avatar_url(login),
        last_login_at: Time.current
      )
      Rails.logger.info "[UserManagement] User '#{user.login}' logged in"
    elsif should_bootstrap_owner?(login)
      # Bootstrap first owner from env var
      user = User.create!(
        github_id: github_id,
        login: login,
        name: auth["info"]["name"],
        avatar_url: auth["info"]["image"] || User.default_avatar_url(login),
        role: :owner,
        last_login_at: Time.current
      )
      Rails.logger.info "[UserManagement] Bootstrapped owner '#{user.login}'"
    else
      # User not in database and not bootstrap - reject
      Rails.logger.warn "[UserManagement] Login rejected for '#{login}' (github_id: #{github_id}) - not authorized"
      redirect_to failure_url("not_authorized"), allow_other_host: true
      return
    end

    # Store user_id in session
    session[:user_id] = user.id
    session[:authenticated_at] = Time.current.iso8601

    redirect_to frontend_url, allow_other_host: true
  end

  def destroy
    reset_session
    redirect_to "#{frontend_url}/login", allow_other_host: true
  end

  def failure
    error = params[:message] || "unknown_error"
    redirect_to failure_url(error), allow_other_host: true
  end

  private

  # Check if this login should bootstrap the first owner
  def should_bootstrap_owner?(login)
    owner_username = ENV["OWNER_GITHUB_USERNAME"]
    return false if owner_username.blank?

    # Only bootstrap if no owners exist yet
    owner_username.downcase == login&.downcase && !User.where(role: :owner).exists?
  end

  def frontend_url
    ENV.fetch("FRONTEND_URL", "http://localhost:3001")
  end

  def failure_url(error)
    "#{frontend_url}/login?error=#{error}"
  end
end
