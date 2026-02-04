# frozen_string_literal: true

# Serializes Sprint data for historical trend analysis.
#
# Supports optional filtering by visible developers and/or team membership.
# When filters are applied, aggregates are recomputed from the filtered set.
#
# Used by:
#   - GET /api/sprints/history (team trends)
#   - Part of DeveloperHistorySerializer (team comparison)
class SprintHistorySerializer
  include DimensionScoreSerializable
  include DeveloperFilterable

  # @param sprint [Sprint] the sprint to serialize
  # @param visible_logins [Array<String>, nil] if set, only include these logins
  # @param team_logins [Array<String>, nil] if set, only include these logins
  def initialize(sprint, visible_logins: nil, team_logins: nil)
    @sprint = sprint
    @visible_logins = visible_logins.present? ? Set.new(visible_logins) : nil
    @team_logins = team_logins.present? ? Set.new(team_logins) : nil
  end

  def as_json
    if filtering?
      devs = filtered_developers
      {
        sprint_label: @sprint.label,
        start_date: @sprint.start_date.to_s,
        end_date: @sprint.end_date.to_s,
        avg_dxi_score: devs.any? ? (devs.sum { |d| d["dxi_score"] || 0 } / devs.size.to_f).round(1) : 0.0,
        dimension_scores: serialize_dimension_scores(DxiCalculator.team_dimension_scores(devs)),
        developer_count: devs.size,
        total_commits: devs.sum { |d| d["commits"] || 0 },
        total_prs: devs.sum { |d| d["prs_opened"] || 0 }
      }
    else
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
end
