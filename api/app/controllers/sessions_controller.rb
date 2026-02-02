# frozen_string_literal: true

class SessionsController < ApplicationController
  def create
    auth = request.env["omniauth.auth"]

    # Verify user is in allowed list (if configured)
    unless authorized_user?(auth["info"]["nickname"])
      redirect_to failure_url("not_authorized"), allow_other_host: true
      return
    end

    # Create or update user record in database
    user = User.find_or_create_from_github(auth)

    # Store user_id in session (not full user hash)
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

  def authorized_user?(username)
    allowed_users = Rails.application.config.opendxi.allowed_users
    return true if allowed_users.empty?

    allowed_users.include?(username.downcase)
  end

  def frontend_url
    ENV.fetch("FRONTEND_URL", "http://localhost:3001")
  end

  def failure_url(error)
    "#{frontend_url}/login?error=#{error}"
  end
end
