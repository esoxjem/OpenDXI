# frozen_string_literal: true

require "test_helper"

class DxiCalculatorTest < ActiveSupport::TestCase
  # ═══════════════════════════════════════════════════════════════════════════
  # Review Turnaround Tests (25% weight)
  # Threshold: <2h = 100, >24h = 0
  # ═══════════════════════════════════════════════════════════════════════════

  test "review_turnaround is 100 at exactly 2 hours" do
    scores = DxiCalculator.dimension_scores({ "avg_review_time_hours" => 2 })
    assert_equal 100.0, scores[:review_turnaround]
  end

  test "review_turnaround is 100 below 2 hours" do
    scores = DxiCalculator.dimension_scores({ "avg_review_time_hours" => 1 })
    assert_equal 100.0, scores[:review_turnaround]
  end

  test "review_turnaround is 100 for nil value" do
    scores = DxiCalculator.dimension_scores({})
    assert_equal 100.0, scores[:review_turnaround]
  end

  test "review_turnaround is 0 at exactly 24 hours" do
    scores = DxiCalculator.dimension_scores({ "avg_review_time_hours" => 24 })
    assert_equal 0.0, scores[:review_turnaround]
  end

  test "review_turnaround clamps at 0 above 24 hours" do
    scores = DxiCalculator.dimension_scores({ "avg_review_time_hours" => 100 })
    assert_equal 0.0, scores[:review_turnaround]
  end

  test "review_turnaround interpolates correctly at midpoint (13h = ~50)" do
    scores = DxiCalculator.dimension_scores({ "avg_review_time_hours" => 13 })
    assert_in_delta 50.0, scores[:review_turnaround], 1.0
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Cycle Time Tests (25% weight)
  # Threshold: <8h = 100, >72h = 0
  # ═══════════════════════════════════════════════════════════════════════════

  test "cycle_time is 100 at exactly 8 hours" do
    scores = DxiCalculator.dimension_scores({ "avg_cycle_time_hours" => 8 })
    assert_equal 100.0, scores[:cycle_time]
  end

  test "cycle_time is 100 below 8 hours" do
    scores = DxiCalculator.dimension_scores({ "avg_cycle_time_hours" => 4 })
    assert_equal 100.0, scores[:cycle_time]
  end

  test "cycle_time is 0 at exactly 72 hours" do
    scores = DxiCalculator.dimension_scores({ "avg_cycle_time_hours" => 72 })
    assert_equal 0.0, scores[:cycle_time]
  end

  test "cycle_time clamps at 0 above 72 hours" do
    scores = DxiCalculator.dimension_scores({ "avg_cycle_time_hours" => 200 })
    assert_equal 0.0, scores[:cycle_time]
  end

  test "cycle_time interpolates correctly at midpoint (40h = ~50)" do
    scores = DxiCalculator.dimension_scores({ "avg_cycle_time_hours" => 40 })
    assert_in_delta 50.0, scores[:cycle_time], 1.0
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PR Size Tests (20% weight)
  # Threshold: <200 lines = 100, >1000 lines = 0
  # ═══════════════════════════════════════════════════════════════════════════

  test "pr_size is 100 for small PRs (150 lines)" do
    scores = DxiCalculator.dimension_scores({
      "lines_added" => 100, "lines_deleted" => 50, "prs_opened" => 1
    })
    assert_equal 100.0, scores[:pr_size]
  end

  test "pr_size is 100 at exactly 200 lines avg" do
    scores = DxiCalculator.dimension_scores({
      "lines_added" => 150, "lines_deleted" => 50, "prs_opened" => 1
    })
    assert_equal 100.0, scores[:pr_size]
  end

  test "pr_size is 0 for large PRs (1200 lines)" do
    scores = DxiCalculator.dimension_scores({
      "lines_added" => 800, "lines_deleted" => 400, "prs_opened" => 1
    })
    assert_equal 0.0, scores[:pr_size]
  end

  test "pr_size handles zero PRs gracefully" do
    scores = DxiCalculator.dimension_scores({ "prs_opened" => 0 })
    assert_equal 100.0, scores[:pr_size]
  end

  test "pr_size handles nil PRs gracefully" do
    scores = DxiCalculator.dimension_scores({})
    assert_equal 100.0, scores[:pr_size]
  end

  test "pr_size calculates average across multiple PRs" do
    # 1000 total lines / 5 PRs = 200 avg
    scores = DxiCalculator.dimension_scores({
      "lines_added" => 700, "lines_deleted" => 300, "prs_opened" => 5
    })
    assert_equal 100.0, scores[:pr_size]
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Review Coverage Tests (15% weight)
  # Threshold: 10+ reviews = 100, linear scale
  # ═══════════════════════════════════════════════════════════════════════════

  test "review_coverage is 100 at exactly 10 reviews" do
    scores = DxiCalculator.dimension_scores({ "reviews_given" => 10 })
    assert_equal 100.0, scores[:review_coverage]
  end

  test "review_coverage is 100 above 10 reviews" do
    scores = DxiCalculator.dimension_scores({ "reviews_given" => 20 })
    assert_equal 100.0, scores[:review_coverage]
  end

  test "review_coverage scales linearly below 10" do
    scores = DxiCalculator.dimension_scores({ "reviews_given" => 5 })
    assert_equal 50.0, scores[:review_coverage]
  end

  test "review_coverage is 0 for zero reviews" do
    scores = DxiCalculator.dimension_scores({ "reviews_given" => 0 })
    assert_equal 0.0, scores[:review_coverage]
  end

  test "review_coverage handles nil gracefully" do
    scores = DxiCalculator.dimension_scores({})
    assert_equal 0.0, scores[:review_coverage]
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Commit Frequency Tests (15% weight)
  # Threshold: 20+ commits = 100, linear scale
  # ═══════════════════════════════════════════════════════════════════════════

  test "commit_frequency is 100 at exactly 20 commits" do
    scores = DxiCalculator.dimension_scores({ "commits" => 20 })
    assert_equal 100.0, scores[:commit_frequency]
  end

  test "commit_frequency is 100 above 20 commits" do
    scores = DxiCalculator.dimension_scores({ "commits" => 50 })
    assert_equal 100.0, scores[:commit_frequency]
  end

  test "commit_frequency scales linearly below 20" do
    scores = DxiCalculator.dimension_scores({ "commits" => 10 })
    assert_equal 50.0, scores[:commit_frequency]
  end

  test "commit_frequency is 0 for zero commits" do
    scores = DxiCalculator.dimension_scores({ "commits" => 0 })
    assert_equal 0.0, scores[:commit_frequency]
  end

  test "commit_frequency handles nil gracefully" do
    scores = DxiCalculator.dimension_scores({})
    assert_equal 0.0, scores[:commit_frequency]
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Composite Score Tests
  # ═══════════════════════════════════════════════════════════════════════════

  test "composite_score applies correct weights" do
    # All dimensions at 100 should yield 100
    scores = {
      review_turnaround: 100, cycle_time: 100, pr_size: 100,
      review_coverage: 100, commit_frequency: 100
    }
    assert_equal 100.0, DxiCalculator.composite_score(scores)
  end

  test "composite_score handles mixed scores" do
    # review_turnaround: 80 * 0.25 = 20
    # cycle_time: 60 * 0.25 = 15
    # pr_size: 40 * 0.20 = 8
    # review_coverage: 100 * 0.15 = 15
    # commit_frequency: 50 * 0.15 = 7.5
    # Total: 65.5
    scores = {
      review_turnaround: 80, cycle_time: 60, pr_size: 40,
      review_coverage: 100, commit_frequency: 50
    }
    assert_equal 65.5, DxiCalculator.composite_score(scores)
  end

  test "composite_score handles all zeros" do
    scores = {
      review_turnaround: 0, cycle_time: 0, pr_size: 0,
      review_coverage: 0, commit_frequency: 0
    }
    assert_equal 0.0, DxiCalculator.composite_score(scores)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Integration Tests (matching Python implementation)
  # ═══════════════════════════════════════════════════════════════════════════

  test "composite score matches Python implementation for known input" do
    metrics = {
      "avg_review_time_hours" => 4.5,
      "avg_cycle_time_hours" => 16.2,
      "lines_added" => 350,
      "lines_deleted" => 120,
      "prs_opened" => 3,
      "reviews_given" => 8,
      "commits" => 15
    }

    scores = DxiCalculator.dimension_scores(metrics)
    composite = DxiCalculator.composite_score(scores)

    # Avg PR size: (350+120)/3 = 156.7 lines (under 200 threshold)
    # These values were verified against Ruby implementation
    assert_in_delta 88.6, scores[:review_turnaround], 0.5
    assert_in_delta 87.2, scores[:cycle_time], 0.5
    assert_equal 100.0, scores[:pr_size]  # 156 lines avg is under 200 threshold
    assert_equal 80.0, scores[:review_coverage]
    assert_equal 75.0, scores[:commit_frequency]
    assert_in_delta 87.2, composite, 1.0
  end

  test "handles all nil/empty values gracefully" do
    scores = DxiCalculator.dimension_scores({})
    assert scores.values.all? { |v| v.is_a?(Numeric) }

    composite = DxiCalculator.composite_score(scores)
    assert composite.is_a?(Numeric)
    # With nil values: review=100, cycle=100, pr_size=100, review_cov=0, commits=0
    # = 25 + 25 + 20 + 0 + 0 = 70
    assert_equal 70.0, composite
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Team Dimension Scores Tests
  # ═══════════════════════════════════════════════════════════════════════════

  test "team_dimension_scores returns averages across developers" do
    developers = [
      { "dimension_scores" => { "review_turnaround" => 100, "cycle_time" => 80, "pr_size" => 60, "review_coverage" => 40, "commit_frequency" => 20 } },
      { "dimension_scores" => { "review_turnaround" => 80, "cycle_time" => 60, "pr_size" => 40, "review_coverage" => 20, "commit_frequency" => 0 } }
    ]

    team_scores = DxiCalculator.team_dimension_scores(developers)

    assert_equal 90.0, team_scores[:review_turnaround]
    assert_equal 70.0, team_scores[:cycle_time]
    assert_equal 50.0, team_scores[:pr_size]
    assert_equal 30.0, team_scores[:review_coverage]
    assert_equal 10.0, team_scores[:commit_frequency]
  end

  test "team_dimension_scores returns defaults for empty developers" do
    team_scores = DxiCalculator.team_dimension_scores([])

    assert_equal 50.0, team_scores[:review_turnaround]
    assert_equal 50.0, team_scores[:cycle_time]
    assert_equal 50.0, team_scores[:pr_size]
    assert_equal 50.0, team_scores[:review_coverage]
    assert_equal 50.0, team_scores[:commit_frequency]
  end
end
