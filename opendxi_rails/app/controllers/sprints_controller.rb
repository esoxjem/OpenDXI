# frozen_string_literal: true

class SprintsController < ApplicationController
  def history
    @sprints = Sprint.recent
    @trend_data = @sprints.reverse.map do |sprint|
      {
        label: sprint.label,
        start_date: sprint.start_date,
        avg_dxi_score: sprint.summary["avg_dxi_score"],
        total_commits: sprint.summary["total_commits"],
        total_prs: sprint.summary["total_prs"],
        total_reviews: sprint.summary["total_reviews"]
      }
    end
  end
end
