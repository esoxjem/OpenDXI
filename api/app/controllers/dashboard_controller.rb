# frozen_string_literal: true

class DashboardController < ApplicationController
  before_action :require_authentication
  before_action :load_sprint_options
  before_action :load_current_sprint

  def index
    @view = params[:view] || "team"

    case @view
    when "team"
      load_team_data
    when "developers"
      load_developers_data
    when "history"
      load_history_data
    end

    # Turbo Frame requests get just the tab content
    if turbo_frame_request?
      render partial: "#{@view}_tab", layout: false
    end
  end

  def refresh
    Sprint.find_or_fetch!(@start_date, @end_date, force: true)
    load_team_data

    redirect_to dashboard_path(sprint: @selected_sprint, view: @view),
                notice: "Data refreshed from GitHub"
  end

  private

  def require_authentication
    unless current_user
      redirect_to login_path, alert: "Please log in to continue"
    end
  end

  def current_user
    return @current_user if defined?(@current_user)

    user = session[:user]
    return @current_user = nil unless user

    # Check session freshness (24 hour expiry)
    authenticated_at = Time.parse(session[:authenticated_at].to_s) rescue nil
    return @current_user = nil if authenticated_at.nil? || authenticated_at < 24.hours.ago

    @current_user = user.with_indifferent_access
  end
  helper_method :current_user

  def load_sprint_options
    @sprints = Sprint.available_sprints
  end

  def load_current_sprint
    @selected_sprint = params[:sprint] || @sprints.first&.dig(:value)
    @start_date, @end_date = @selected_sprint&.split("|")
  end

  def load_team_data
    return unless @start_date && @end_date

    sprint = Sprint.find_or_fetch!(@start_date, @end_date)
    @metrics = sprint_to_view_data(sprint)
    @previous_metrics = load_previous_sprint_data
  end

  def load_developers_data
    load_team_data
    @selected_developer = params[:developer]
    @developer = @metrics&.dig(:developers)&.find { |d| d[:developer] == @selected_developer }
  end

  def load_history_data
    @sprint_history = load_sprint_history(count: 6)
  end

  def load_previous_sprint_data
    prev_start = Date.parse(@start_date) - 14.days
    prev_end = Date.parse(@end_date) - 14.days
    prev_sprint = Sprint.find_by(start_date: prev_start, end_date: prev_end)
    prev_sprint ? sprint_to_view_data(prev_sprint)[:summary] : nil
  rescue Date::Error => e
    Rails.logger.warn("Invalid date for previous sprint: #{e.message}")
    nil
  end

  def load_sprint_history(count:)
    sprints = Sprint.available_sprints(limit: count)
    sprints.map do |s|
      sprint = Sprint.find_by(start_date: s[:start_date], end_date: s[:end_date])
      next nil unless sprint

      data = sprint_to_view_data(sprint)
      {
        label: s[:label],
        start_date: s[:start_date],
        end_date: s[:end_date],
        avg_dxi_score: data.dig(:summary, :avg_dxi_score)&.round(1),
        total_commits: data.dig(:summary, :total_commits),
        total_prs: data.dig(:summary, :total_prs),
        total_reviews: data.dig(:summary, :total_reviews)
      }
    end.compact
  end

  def sprint_to_view_data(sprint)
    MetricsResponseSerializer.new(sprint).as_json
  end
end
