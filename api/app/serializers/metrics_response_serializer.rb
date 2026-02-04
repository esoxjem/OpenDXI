# frozen_string_literal: true

# Serializes Sprint data to match the FastAPI MetricsResponse contract.
#
# Supports optional filtering by visible developers and/or team membership.
# When filters are applied, summary stats and team dimension scores are
# recomputed from the filtered developer set.
#
# Key transformations:
#   - `daily_activity` -> `daily` (field rename)
#   - `review_turnaround` -> `review_speed` (dimension score rename)
#   - `github_login` -> `developer` (developer identifier)
class MetricsResponseSerializer
  include DimensionScoreSerializable

  # @param sprint [Sprint] the sprint to serialize
  # @param visible_logins [Array<String>, nil] if set, only include these logins
  # @param team_logins [Array<String>, nil] if set, only include these logins
  # @param team_name [String, nil] team name for filter_meta display
  def initialize(sprint, visible_logins: nil, team_logins: nil, team_name: nil)
    @sprint = sprint
    @visible_logins = visible_logins
    @team_logins = team_logins
    @team_name = team_name
  end

  def as_json
    devs = filtered_developers
    filtered = filtering?

    result = {
      developers: devs.map { |d| serialize_developer(d) },
      daily: @sprint.daily_activity,
      summary: filtered ? recompute_summary(devs) : serialize_summary(@sprint.summary),
      team_dimension_scores: filtered ? recompute_dimension_scores(devs) : serialize_dimension_scores(@sprint.team_dimension_scores)
    }

    result[:filter_meta] = build_filter_meta(devs) if filtered
    result
  end

  private

  def filtering?
    @visible_logins.present? || @team_logins.present?
  end

  def filtered_developers
    devs = @sprint.developers
    devs = devs.select { |d| developer_login(d).in?(@visible_logins) } if @visible_logins.present?
    devs = devs.select { |d| developer_login(d).in?(@team_logins) } if @team_logins.present?
    devs
  end

  def developer_login(dev)
    dev["github_login"] || dev["developer"]
  end

  def serialize_developer(dev)
    {
      developer: developer_login(dev),
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

  def recompute_summary(devs)
    {
      total_commits: devs.sum { |d| d["commits"] || 0 },
      total_prs: devs.sum { |d| d["prs_opened"] || 0 },
      total_merged: devs.sum { |d| d["prs_merged"] || 0 },
      total_reviews: devs.sum { |d| d["reviews_given"] || 0 },
      avg_dxi_score: devs.any? ? (devs.sum { |d| d["dxi_score"] || 0 } / devs.size.to_f).round(1) : 0.0
    }
  end

  def recompute_dimension_scores(devs)
    serialize_dimension_scores(DxiCalculator.team_dimension_scores(devs))
  end

  def build_filter_meta(filtered_devs)
    meta = {
      total_developers: @sprint.developers.size,
      showing_developers: filtered_devs.size
    }

    meta[:team_name] = @team_name if @team_name.present?
    meta
  end
end
