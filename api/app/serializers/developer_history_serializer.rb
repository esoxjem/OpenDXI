# frozen_string_literal: true

# Serializes a developer's historical metrics across multiple sprints.
#
# Used by: GET /api/developers/:name/history
#
# Returns both the developer's personal history and team history for comparison.
class DeveloperHistorySerializer
  include DimensionScoreSerializable

  def initialize(developer_name, sprints)
    @developer_name = developer_name
    @sprints = sprints
  end

  def as_json
    {
      developer: @developer_name,
      sprints: developer_sprint_entries,
      team_history: team_sprint_entries
    }
  end

  private

  def developer_sprint_entries
    @sprints.filter_map do |sprint|
      dev = sprint.find_developer(@developer_name)
      next unless dev

      {
        sprint_label: sprint.label,
        start_date: sprint.start_date.to_s,
        end_date: sprint.end_date.to_s,
        dxi_score: dev["dxi_score"] || 0.0,
        dimension_scores: serialize_dimension_scores(dev["dimension_scores"]),
        commits: dev["commits"] || 0,
        prs_opened: dev["prs_opened"] || 0,
        prs_merged: dev["prs_merged"] || 0,
        reviews_given: dev["reviews_given"] || 0,
        lines_added: dev["lines_added"] || 0,
        lines_deleted: dev["lines_deleted"] || 0,
        avg_review_time_hours: dev["avg_review_time_hours"],
        avg_cycle_time_hours: dev["avg_cycle_time_hours"]
      }
    end
  end

  def team_sprint_entries
    @sprints.map { |sprint| SprintHistorySerializer.new(sprint).as_json }
  end
end
