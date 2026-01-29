# frozen_string_literal: true

class SessionsController < ApplicationController
  # GET /login
  def new
    # In dev mode without OAuth, auto-redirect to dashboard
    if dev_mode?
      session[:user] = dev_user
      session[:authenticated_at] = Time.current.iso8601
      redirect_to root_path, notice: "Signed in as Development User"
      return
    end

    # Already logged in? Go to dashboard
    redirect_to root_path if logged_in?
  end

  # POST /auth/github/callback
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
      redirect_to login_path, alert: "You are not authorized to access this application"
      return
    end

    session[:user] = user_info
    session[:authenticated_at] = Time.current.iso8601

    redirect_to root_path, notice: "Signed in successfully"
  end

  # DELETE /auth/logout
  def destroy
    reset_session

    # In dev mode, just redirect back to root (will auto-login)
    if dev_mode?
      redirect_to root_path
    else
      redirect_to login_path, notice: "Signed out successfully"
    end
  end

  # GET /auth/failure
  def failure
    error = params[:message] || "unknown_error"
    alert_message = case error
    when "not_authorized"
      "You are not authorized to access this application"
    when "invalid_credentials"
      "Invalid credentials. Please try again."
    else
      "Authentication failed. Please try again."
    end

    redirect_to login_path, alert: alert_message
  end

  private

  def authorized_user?(username)
    allowed_users = Rails.application.config.opendxi.allowed_users
    return true if allowed_users.empty?

    allowed_users.include?(username.downcase)
  end
end
