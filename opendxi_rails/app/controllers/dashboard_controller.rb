# frozen_string_literal: true

class DashboardController < ApplicationController
  def show
    @sprint = find_or_current_sprint
    @sprints = Sprint.available_sprints
    @view = params[:view] || "team"
    @sort_by = params[:sort] || "dxi_score"
    @sort_dir = params[:dir] || "desc"
  end

  def refresh
    start_date, end_date = parse_sprint_dates
    @sprint = Sprint.find_or_fetch!(start_date, end_date, force: true)
    @sprints = Sprint.available_sprints
    @view = params[:view] || "team"
    @sort_by = params[:sort] || "dxi_score"
    @sort_dir = params[:dir] || "desc"

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("metrics-content", partial: "dashboard/metrics", locals: { sprint: @sprint, view: @view }),
          turbo_stream.replace("flash", partial: "shared/flash", locals: { notice: "Data refreshed successfully" })
        ]
      end
      format.html { redirect_to dashboard_path(sprint: @sprint.date_range_param), notice: "Data refreshed" }
    end
  rescue GithubService::GhCliNotFound, GithubService::GitHubApiError => e
    handle_github_error(e)
  end

  private

  def find_or_current_sprint
    if params[:sprint].present?
      start_date, end_date = params[:sprint].split("|")
      Sprint.find_or_fetch!(start_date, end_date)
    else
      start_date, end_date = Sprint.current_sprint_dates
      Sprint.find_by_dates(start_date, end_date) || create_placeholder_sprint(start_date, end_date)
    end
  rescue GithubService::GhCliNotFound, GithubService::GitHubApiError => e
    handle_github_error(e)
    create_placeholder_sprint(*Sprint.current_sprint_dates)
  end

  def parse_sprint_dates
    if params[:sprint].present?
      params[:sprint].split("|")
    else
      Sprint.current_sprint_dates
    end
  end

  def create_placeholder_sprint(start_date, end_date)
    Sprint.find_or_create_by!(start_date: start_date, end_date: end_date) do |s|
      s.data = GithubService.send(:empty_response)
    end
  end

  def handle_github_error(error)
    message = case error
    when GithubService::GhCliNotFound
                error.message
    when GithubService::RateLimitExceeded
                "GitHub API rate limit exceeded. Please try again later."
    when GithubService::AuthenticationError
                "GitHub authentication failed. Please run 'gh auth login'."
    else
                "Failed to fetch data from GitHub: #{error.message}"
    end

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("flash", partial: "shared/flash", locals: { alert: message })
      end
      format.html { redirect_to dashboard_path, alert: message }
    end
  end
end
