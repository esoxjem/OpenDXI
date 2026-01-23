# frozen_string_literal: true

# Handles GitHub OAuth callbacks and session management
#
# OAuth flow:
#   1. User clicks "Sign in with GitHub" (POST /auth/github via form)
#   2. OmniAuth redirects to GitHub for authorization
#   3. GitHub redirects back to /auth/github/callback (this controller)
#   4. We verify the user is in the allowed list and create a session
#   5. User is redirected to the frontend
class SessionsController < ApplicationController
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
      redirect_to failure_url("not_authorized"), allow_other_host: true
      return
    end

    # Create session (OAuth token NOT stored - security best practice)
    session[:user] = user_info
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
