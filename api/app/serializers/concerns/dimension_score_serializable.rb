# frozen_string_literal: true

# Shared serialization logic for DXI dimension scores.
#
# Dimension scores are stored with internal names (e.g., "review_turnaround")
# but the API contract uses display names (e.g., "review_speed").
#
# This module handles:
#   - Field name mapping (review_turnaround -> review_speed)
#   - String/symbol key indifference (from JSON vs. Ruby hash sources)
#   - Default values for missing scores
module DimensionScoreSerializable
  def serialize_dimension_scores(scores)
    return nil unless scores

    {
      review_speed: scores["review_turnaround"] || scores[:review_turnaround] || 0.0,
      cycle_time: scores["cycle_time"] || scores[:cycle_time] || 0.0,
      pr_size: scores["pr_size"] || scores[:pr_size] || 0.0,
      review_coverage: scores["review_coverage"] || scores[:review_coverage] || 0.0,
      commit_frequency: scores["commit_frequency"] || scores[:commit_frequency] || 0.0
    }
  end
end
