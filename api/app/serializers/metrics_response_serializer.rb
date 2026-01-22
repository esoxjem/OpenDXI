# frozen_string_literal: true

# Serializes Sprint data to match the FastAPI MetricsResponse contract.
#
# Key transformations:
#   - `daily_activity` -> `daily` (field rename)
#   - `review_turnaround` -> `review_speed` (dimension score rename)
#   - `github_login` -> `developer` (developer identifier)
class MetricsResponseSerializer
  include DimensionScoreSerializable

  def initialize(sprint)
    @sprint = sprint
  end

  def as_json
    {
      developers: @sprint.developers.map { |d| serialize_developer(d) },
      daily: @sprint.daily_activity,
      summary: serialize_summary(@sprint.summary),
      team_dimension_scores: serialize_dimension_scores(@sprint.team_dimension_scores)
    }
  end

  private

  def serialize_developer(dev)
    {
      developer: dev["github_login"] || dev["developer"],
      commits: dev["commits"] || 0,
      prs_opened: dev["prs_opened"] || 0,
      prs_merged: dev["prs_merged"] || 0,
      reviews_given: dev["reviews_given"] || 0,
      lines_added: dev["lines_added"] || 0,
      lines_deleted: dev["lines_deleted"] || 0,
      avg_review_time_hours: dev["avg_review_time_hours"],
      avg_cycle_time_hours: dev["avg_cycle_time_hours"],
      dxi_score: dev["dxi_score"] || 0.0,
      dimension_scores: serialize_dimension_scores(dev["dimension_scores"])
    }
  end

  def serialize_summary(summary)
    {
      total_commits: summary["total_commits"] || 0,
      total_prs: summary["total_prs"] || 0,
      total_merged: summary["total_merged"] || 0,
      total_reviews: summary["total_reviews"] || 0,
      avg_dxi_score: summary["avg_dxi_score"] || 0.0
    }
  end
end
