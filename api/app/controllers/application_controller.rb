class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Global error handling for GitHub service errors
  rescue_from GithubService::GhCliNotFound, with: :handle_gh_cli_error
  rescue_from GithubService::GitHubApiError, with: :handle_github_error

  private

  def handle_gh_cli_error(error)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("flash",
          partial: "shared/flash",
          locals: { alert: error.message })
      end
      format.html { redirect_back fallback_location: root_path, alert: error.message }
    end
  end

  def handle_github_error(error)
    message = case error
    when GithubService::RateLimitExceeded
                "GitHub API rate limit exceeded. Please try again later."
    when GithubService::AuthenticationError
                "GitHub authentication failed. Please run 'gh auth login'."
    else
                "Failed to fetch data from GitHub. Please try again."
    end

    Rails.logger.error("GitHub API Error: #{error.message}")

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("flash",
          partial: "shared/flash",
          locals: { alert: message })
      end
      format.html { redirect_back fallback_location: root_path, alert: message }
    end
  end
end
