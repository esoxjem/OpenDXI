# frozen_string_literal: true

class DevelopersController < ApplicationController
  def show
    @sprint = find_sprint
    @developer = @sprint&.find_developer(params[:login])

    if @developer.nil?
      redirect_to dashboard_path, alert: "Developer not found"
      return
    end

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def history
    @login = params[:login]
    @sprints = Sprint.recent.select { |s| s.find_developer(@login).present? }
    @history = @sprints.map do |sprint|
      dev = sprint.find_developer(@login)
      {
        sprint_label: sprint.label,
        start_date: sprint.start_date,
        dxi_score: dev["dxi_score"],
        commits: dev["commits"],
        prs_opened: dev["prs_opened"],
        reviews_given: dev["reviews_given"]
      }
    end
  end

  private

  def find_sprint
    if params[:sprint].present?
      start_date, end_date = params[:sprint].split("|")
      Sprint.find_by_dates(start_date, end_date)
    else
      Sprint.current.first || Sprint.recent.first
    end
  end
end
