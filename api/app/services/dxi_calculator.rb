# frozen_string_literal: true

# DXI (Developer Experience Index) Calculator
#
# Calculates developer productivity scores across five weighted dimensions:
# - Review Turnaround (25%): Time to first review (<2h = 100, >24h = 0)
# - PR Cycle Time (25%): PR open to merge duration (<8h = 100, >72h = 0)
# - PR Size (20%): Lines changed per PR (<200 = 100, >1000 = 0)
# - Review Coverage (15%): Reviews given per sprint (10+ = 100)
# - Commit Frequency (15%): Commits per sprint (20+ = 100)
#
# Score ranges: 70+ good, 50-70 moderate, <50 needs improvement
class DxiCalculator
  WEIGHTS = {
    review_turnaround: 0.25,
    cycle_time: 0.25,
    pr_size: 0.20,
    review_coverage: 0.15,
    commit_frequency: 0.15
  }.freeze

  THRESHOLDS = {
    review_time: { min: 2, max: 24 },    # hours
    cycle_time: { min: 8, max: 72 },     # hours
    pr_size: { min: 200, max: 1000 },    # lines
    reviews: { target: 10 },              # count
    commits: { target: 20 }               # count
  }.freeze

  class << self
    # Calculate composite DXI score from dimension scores
    # @param dimension_scores [Hash] scores for each dimension (0-100)
    # @return [Float] weighted composite score (0-100)
    def composite_score(dimension_scores)
      WEIGHTS.sum { |dim, weight| (dimension_scores[dim] || 0) * weight }.round(1)
    end

    # Calculate individual dimension scores for a developer
    # @param metrics [Hash] developer activity metrics
    # @return [Hash] scores for each dimension (0-100)
    def dimension_scores(metrics)
      metrics = metrics.with_indifferent_access if metrics.respond_to?(:with_indifferent_access)

      {
        review_turnaround: review_turnaround_score(metrics["avg_review_time_hours"]),
        cycle_time: cycle_time_score(metrics["avg_cycle_time_hours"]),
        pr_size: pr_size_score(metrics["lines_added"], metrics["lines_deleted"], metrics["prs_opened"]),
        review_coverage: review_coverage_score(metrics["reviews_given"]),
        commit_frequency: commit_frequency_score(metrics["commits"])
      }
    end

    # Calculate team-level dimension scores (average of all developers)
    # @param developers [Array<Hash>] list of developer metrics with dimension_scores
    # @return [Hash] average scores for each dimension
    def team_dimension_scores(developers)
      return empty_team_scores if developers.empty?

      dimensions = %i[review_turnaround cycle_time pr_size review_coverage commit_frequency]
      dimensions.index_with do |dim|
        scores = developers.map { |d| d.dig("dimension_scores", dim.to_s) || d.dig(:dimension_scores, dim) || 0 }
        (scores.sum / scores.size.to_f).round(1)
      end
    end

    private

    def empty_team_scores
      {
        review_turnaround: 50.0,
        cycle_time: 50.0,
        pr_size: 50.0,
        review_coverage: 50.0,
        commit_frequency: 50.0
      }
    end

    # Review turnaround: <2h = 100, >24h = 0
    def review_turnaround_score(hours)
      return 100.0 if hours.nil? || hours <= THRESHOLDS[:review_time][:min]
      normalize_inverse(hours, THRESHOLDS[:review_time][:min], THRESHOLDS[:review_time][:max])
    end

    # Cycle time: <8h = 100, >72h = 0
    def cycle_time_score(hours)
      return 100.0 if hours.nil? || hours <= THRESHOLDS[:cycle_time][:min]
      normalize_inverse(hours, THRESHOLDS[:cycle_time][:min], THRESHOLDS[:cycle_time][:max])
    end

    # PR size: <200 lines = 100, >1000 lines = 0
    def pr_size_score(lines_added, lines_deleted, prs_opened)
      return 100.0 if prs_opened.nil? || prs_opened.zero?

      avg_size = ((lines_added || 0) + (lines_deleted || 0)) / prs_opened.to_f
      return 100.0 if avg_size <= THRESHOLDS[:pr_size][:min]

      normalize_inverse(avg_size, THRESHOLDS[:pr_size][:min], THRESHOLDS[:pr_size][:max])
    end

    # Review coverage: 10+ reviews = 100, linear scale below
    def review_coverage_score(reviews)
      return 0.0 if reviews.nil?
      [ reviews * 10.0, 100.0 ].min
    end

    # Commit frequency: 20+ commits = 100, linear scale below
    def commit_frequency_score(commits)
      return 0.0 if commits.nil?
      [ commits * 5.0, 100.0 ].min
    end

    # Inverse normalization: lower values = higher scores
    # Formula: 100 - ((value - min) / (max - min)) * 100
    def normalize_inverse(value, min, max)
      score = 100.0 - ((value - min) * (100.0 / (max - min)))
      [ [ 0.0, score ].max, 100.0 ].min.round(1)
    end
  end
end
