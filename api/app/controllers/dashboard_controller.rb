# frozen_string_literal: true

# Main dashboard controller for the OpenDXI metrics display.
#
# Renders server-side HTML views with Hotwire for navigation.
# Replaces the Next.js SPA frontend with traditional Rails views.
class DashboardController < ApplicationController
  before_action :authenticate!
  before_action :set_sprint_dates
  before_action :set_available_sprints

  # Handle GitHub API errors gracefully - show cached data with warning
  rescue_from GithubService::GitHubApiError do |error|
    Rails.logger.error("GitHub API error: #{error.message}")
    flash.now[:alert] = "GitHub API error. Showing cached data."

    # Try to load cached data
    @sprint = Sprint.find_by_dates(@start_date, @end_date)
    if @sprint
      calculate_kpi_values
      load_previous_sprint_for_trends
    end

    render :show
  end

  rescue_from ActiveRecord::RecordNotFound do
    redirect_to dashboard_path, alert: "Resource not found"
  end

  # GET / or GET /dashboard
  #
  # Main dashboard view with tab-based navigation.
  # Tabs: team (default), developers, history
  def show
    @tab = params[:tab] || "team"

    case @tab
    when "team", "developers"
      load_sprint_data
      load_developer_detail if @tab == "developers" && params[:developer].present?
    when "history"
      load_history_data
    end
  end

  # POST /dashboard/refresh
  #
  # Force refresh sprint data from GitHub API.
  def refresh
    Sprint.find_or_fetch!(@start_date, @end_date, force: true)
    redirect_to dashboard_path(sprint: params[:sprint], tab: params[:tab]), notice: "Data refreshed"
  rescue StandardError => e
    Rails.logger.error("Dashboard refresh failed: #{e.message}")
    redirect_to dashboard_path(sprint: params[:sprint], tab: params[:tab]), alert: "Failed to refresh data"
  end

  private

  def set_sprint_dates
    if params[:sprint].present?
      dates = params[:sprint].split("|")
      @start_date = Date.parse(dates[0])
      @end_date = Date.parse(dates[1])
    else
      @start_date, @end_date = Sprint.current_sprint_dates
    end
  rescue ArgumentError
    @start_date, @end_date = Sprint.current_sprint_dates
  end

  def set_available_sprints
    @sprints = Sprint.available_sprints
  end

  def load_sprint_data
    @sprint = Sprint.find_or_fetch!(@start_date, @end_date)
    calculate_kpi_values
    load_previous_sprint_for_trends
  end

  def load_developer_detail
    @selected_developer = @sprint.find_developer(params[:developer])
    unless @selected_developer
      redirect_to dashboard_path(tab: "developers", sprint: params[:sprint]), alert: "Developer not found"
    end
  end

  def load_history_data
    @sprint_history = Sprint.order(start_date: :desc).limit(6).reverse
  end

  def calculate_kpi_values
    return unless @sprint

    @summary = @sprint.summary
    @developers = @sprint.developers
    @daily_activity = @sprint.daily_activity
    @team_dimension_scores = @sprint.team_dimension_scores

    # Calculate average cycle time and review time
    cycle_times = @developers.map { |d| d["avg_cycle_time_hours"] }.compact
    @avg_cycle_time = cycle_times.any? ? (cycle_times.sum / cycle_times.size).round(1) : nil

    review_times = @developers.map { |d| d["avg_review_time_hours"] }.compact
    @avg_review_time = review_times.any? ? (review_times.sum / review_times.size).round(1) : nil
  end

  def load_previous_sprint_for_trends
    @previous_sprint = Sprint.where("end_date < ?", @start_date).order(end_date: :desc).first
    return unless @previous_sprint

    @prev_summary = @previous_sprint.summary
    @prev_dimension_scores = @previous_sprint.team_dimension_scores
  end
end
