# frozen_string_literal: true

# Base application controller for HTML views.
# Note: API controllers inherit from Api::BaseController (ActionController::API),
# not this controller.
class ApplicationController < ActionController::Base
  helper_method :current_user, :logged_in?, :dev_mode?

  private

  def current_user
    @current_user ||= session[:user]
  end

  def logged_in?
    current_user.present?
  end

  def authenticate!
    # Auto-login in dev mode when OAuth is not configured
    if dev_mode? && !logged_in?
      session[:user] = dev_user
      session[:authenticated_at] = Time.current.iso8601
      return
    end

    return if logged_in?
    redirect_to login_path, alert: "Please sign in to continue"
  end

  # Development mode: OAuth not configured
  def dev_mode?
    Rails.env.development? && ENV["GITHUB_OAUTH_CLIENT_ID"].blank?
  end

  def dev_user
    {
      github_id: "dev-user-123",
      login: "dev-user",
      name: "Development User",
      avatar_url: nil
    }
  end
end
