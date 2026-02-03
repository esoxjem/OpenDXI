# frozen_string_literal: true

# Base controller for all API endpoints
#
# Inherits from ActionController::API for a slimmer middleware stack.
# Provides authentication, consistent JSON error handling, and rate limiting for all API responses.
module Api
  class BaseController < ActionController::API
    include ActionController::Cookies

    # Rate limiting: 100 requests per minute per IP for general API access
    rate_limit to: 100, within: 1.minute, by: -> { request.remote_ip }, with: -> { api_rate_limited }

    # Authentication: All API endpoints require login by default
    before_action :authenticate!

    rescue_from ActiveRecord::RecordNotFound, with: :not_found
    rescue_from ActionController::ParameterMissing, with: :bad_request
    rescue_from ArgumentError, with: :bad_request
    rescue_from Date::Error, with: :bad_request
    rescue_from GithubService::RateLimitExceeded, with: :rate_limited
    rescue_from GithubService::AuthenticationError, with: :github_auth_error
    rescue_from GithubService::GitHubApiError, with: :github_error

    private

    # Maximum session age before requiring re-authentication
    SESSION_MAX_AGE = 24.hours

    def authenticate!
      # Skip authentication entirely in development when SKIP_AUTH is set
      return if skip_auth?

      # Check if user had a session but was deleted (access revoked)
      # Must check BEFORE current_user because current_user returns nil for deleted users
      if session[:user_id] && !user_still_authorized?
        reset_session
        return render json: {
          error: "access_revoked",
          detail: "Your access has been revoked. Please contact an administrator.",
          login_url: "/auth/github"
        }, status: :unauthorized
      end

      unless current_user
        return render json: {
          error: "unauthorized",
          detail: "Please log in to access this resource",
          login_url: "/auth/github"
        }, status: :unauthorized
      end
    end

    def skip_auth?
      return false unless Rails.env.development?

      # Explicit skip via environment variable
      return true if ENV["SKIP_AUTH"] == "true"

      # Auto-skip when GitHub OAuth is not configured (development convenience)
      # This allows local dev to work without setting up OAuth credentials
      !github_oauth_configured?
    end

    def github_oauth_configured?
      ENV["GITHUB_OAUTH_CLIENT_ID"].to_s.strip.present? &&
        ENV["GITHUB_OAUTH_CLIENT_SECRET"].to_s.strip.present?
    end

    def current_user
      return @current_user if defined?(@current_user)

      if skip_auth?
        # Dev mode: return unpersisted User instance with owner role for testing
        return @current_user = User.new(
          id: 0,
          github_id: 0,
          login: "dev-user",
          name: "Local Developer",
          avatar_url: "",
          role: :owner
        )
      end

      # New session format: user_id references User record
      if session[:user_id]
        # Validate session age
        authenticated_at = Time.parse(session[:authenticated_at].to_s) rescue nil
        if authenticated_at.nil? || authenticated_at < SESSION_MAX_AGE.ago
          reset_session
          return @current_user = nil
        end

        return @current_user = User.find_by(id: session[:user_id])
      end

      # Legacy session format: clear and require re-auth
      if session[:user]
        reset_session
        return @current_user = nil
      end

      @current_user = nil
    end

    def require_owner!
      head :forbidden unless current_user&.owner?
    end

    def user_still_authorized?
      # When auth is skipped (dev mode), always authorized
      return true if skip_auth?

      # Database is the single source of truth - check user still exists
      User.exists?(id: session[:user_id])
    end

    def api_rate_limited
      render json: {
        error: "rate_limited",
        detail: "API rate limit exceeded. Maximum 100 requests per minute."
      }, status: :too_many_requests
    end

    def not_found(exception)
      render json: { error: "not_found", detail: exception.message }, status: :not_found
    end

    def bad_request(exception)
      render json: { error: "bad_request", detail: exception.message }, status: :bad_request
    end

    def rate_limited(_exception)
      render json: {
        error: "rate_limited",
        detail: "GitHub API rate limit exceeded. Please try again later."
      }, status: :too_many_requests
    end

    def github_auth_error(_exception)
      render json: {
        error: "authentication_error",
        detail: "GitHub authentication failed. Please check GH_TOKEN."
      }, status: :bad_gateway
    end

    def github_error(exception)
      Rails.logger.error("GitHub API Error: #{exception.message}")
      render json: {
        error: "github_api_error",
        detail: "Failed to fetch data from GitHub. Please try again."
      }, status: :bad_gateway
    end
  end
end
