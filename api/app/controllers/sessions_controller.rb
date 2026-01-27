# frozen_string_literal: true

class SessionsController < ApplicationController
  def new
    # Login page - already logged in users go to dashboard
    redirect_to root_path if session[:user].present?
  end

  def create
    auth = request.env["omniauth.auth"]

    user_info = {
      github_id: auth["uid"],
      login: auth["info"]["nickname"],
      name: auth["info"]["name"],
      avatar_url: auth["info"]["image"]
    }

    # Verify user is in allowed list (if configured)
    unless authorized_user?(user_info[:login])
      redirect_to login_path(error: "not_authorized")
      return
    end

    session[:user] = user_info
    session[:authenticated_at] = Time.current.iso8601

    redirect_to root_path, notice: "Logged in as #{user_info[:login]}"
  end

  def destroy
    reset_session
    redirect_to login_path, notice: "Logged out successfully"
  end

  def failure
    error = params[:message] || "unknown_error"
    redirect_to login_path(error: error)
  end

  private

  def authorized_user?(username)
    allowed_users = Rails.application.config.opendxi.allowed_users
    return true if allowed_users.empty?

    allowed_users.include?(username.downcase)
  end
end
