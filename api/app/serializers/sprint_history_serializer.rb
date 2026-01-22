# frozen_string_literal: true

# Serializes Sprint data for historical trend analysis.
#
# Used by:
#   - GET /api/sprints/history (team trends)
#   - Part of DeveloperHistorySerializer (team comparison)
class SprintHistorySerializer
  include DimensionScoreSerializable

  def initialize(sprint)
    @sprint = sprint
  end

  def as_json
    summary = @sprint.summary

    {
      sprint_label: @sprint.label,
      start_date: @sprint.start_date.to_s,
      end_date: @sprint.end_date.to_s,
      avg_dxi_score: summary["avg_dxi_score"] || 0.0,
      dimension_scores: serialize_dimension_scores(@sprint.team_dimension_scores),
      developer_count: summary["developer_count"] || @sprint.developers.size,
      total_commits: summary["total_commits"] || 0,
      total_prs: summary["total_prs"] || 0
    }
  end
end
