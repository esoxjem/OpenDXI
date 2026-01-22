# frozen_string_literal: true

# Base controller for all API endpoints
#
# Inherits from ActionController::API for a slimmer middleware stack.
# Provides consistent JSON error handling and rate limiting for all API responses.
module Api
  class BaseController < ActionController::API
    # Rate limiting: 100 requests per minute per IP for general API access
    rate_limit to: 100, within: 1.minute, by: -> { request.remote_ip }, with: -> { api_rate_limited }

    rescue_from ActiveRecord::RecordNotFound, with: :not_found
    rescue_from ActionController::ParameterMissing, with: :bad_request
    rescue_from ArgumentError, with: :bad_request
    rescue_from Date::Error, with: :bad_request
    rescue_from GithubService::GhCliNotFound, with: :gh_cli_missing
    rescue_from GithubService::RateLimitExceeded, with: :rate_limited
    rescue_from GithubService::AuthenticationError, with: :github_auth_error
    rescue_from GithubService::GitHubApiError, with: :github_error

    private

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

    def gh_cli_missing(exception)
      render json: {
        error: "configuration_error",
        detail: exception.message
      }, status: :service_unavailable
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
        detail: "GitHub authentication failed. Please run 'gh auth login'."
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
