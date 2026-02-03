# frozen_string_literal: true

# Returns authentication status for the current session
#
# This endpoint allows the frontend to check if the user is logged in
# and get basic user info without triggering a redirect.
module Api
  class AuthController < BaseController
    skip_before_action :authenticate!, only: [:me]

    # GET /api/auth/me
    # Returns current user info or 401 with login URL
    def me
      # Check for access revoked FIRST - before current_user
      # This catches the case where a user had a session but was deleted
      if session[:user_id] && !user_still_authorized?
        reset_session
        return render json: {
          authenticated: false,
          error: "access_revoked",
          detail: "Your access has been revoked.",
          login_url: "/auth/github"
        }, status: :unauthorized
      end

      if current_user
        render json: {
          authenticated: true,
          user: {
            id: current_user.id,
            github_id: current_user.github_id,
            login: current_user.login,
            name: current_user.name,
            avatar_url: current_user.avatar_url,
            role: current_user.role
          }
        }
      else
        render json: { authenticated: false, login_url: "/auth/github" }, status: :unauthorized
      end
    end
  end
end
