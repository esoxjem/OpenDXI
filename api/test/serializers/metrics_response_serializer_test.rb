# frozen_string_literal: true

require "test_helper"

class MetricsResponseSerializerTest < ActiveSupport::TestCase
  setup do
    @sprint = Sprint.create!(
      start_date: Date.new(2026, 3, 1),
      end_date: Date.new(2026, 3, 14),
      data: {
        "developers" => [
          developer_data("alice", commits: 10, dxi_score: 80.0),
          developer_data("bob", commits: 8, dxi_score: 70.0),
          developer_data("charlie", commits: 4, dxi_score: 55.0)
        ],
        "daily_activity" => [{ "date" => "2026-03-01", "commits" => 5 }],
        "summary" => {
          "total_commits" => 22,
          "total_prs" => 6,
          "total_merged" => 5,
          "total_reviews" => 9,
          "developer_count" => 3,
          "avg_dxi_score" => 68.3
        },
        "team_dimension_scores" => {
          "review_turnaround" => 71.7,
          "cycle_time" => 63.3,
          "pr_size" => 81.7,
          "review_coverage" => 30.0,
          "commit_frequency" => 36.7
        }
      }
    )
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Unfiltered (backwards compatible)
  # ═══════════════════════════════════════════════════════════════════════════

  test "returns all developers when no filters applied" do
    json = MetricsResponseSerializer.new(@sprint).as_json

    assert_equal 3, json[:developers].size
    names = json[:developers].map { |d| d[:developer] }
    assert_equal %w[alice bob charlie], names.sort
  end

  test "uses stored summary when no filters applied" do
    json = MetricsResponseSerializer.new(@sprint).as_json

    assert_equal 22, json[:summary][:total_commits]
    assert_equal 68.3, json[:summary][:avg_dxi_score]
  end

  test "does not include filter_meta when no filters applied" do
    json = MetricsResponseSerializer.new(@sprint).as_json

    assert_not json.key?(:filter_meta)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Visibility filtering
  # ═══════════════════════════════════════════════════════════════════════════

  test "filters to visible logins only" do
    json = MetricsResponseSerializer.new(@sprint, visible_logins: %w[alice bob]).as_json

    names = json[:developers].map { |d| d[:developer] }
    assert_equal %w[alice bob], names.sort
    refute_includes names, "charlie"
  end

  test "recomputes summary for visible set" do
    json = MetricsResponseSerializer.new(@sprint, visible_logins: %w[alice]).as_json

    assert_equal 10, json[:summary][:total_commits]
    assert_equal 80.0, json[:summary][:avg_dxi_score]
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Team filtering
  # ═══════════════════════════════════════════════════════════════════════════

  test "filters to team logins only" do
    json = MetricsResponseSerializer.new(@sprint, team_logins: %w[alice bob]).as_json

    names = json[:developers].map { |d| d[:developer] }
    assert_equal 2, names.size
    refute_includes names, "charlie"
  end

  test "recomputes team_dimension_scores for filtered set" do
    # With only alice, dimension scores should reflect her scores alone
    json = MetricsResponseSerializer.new(@sprint, team_logins: %w[alice]).as_json

    scores = json[:team_dimension_scores]
    assert_equal 85.0, scores[:review_speed]
    assert_equal 75.0, scores[:cycle_time]
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Combined filters (visibility + team)
  # ═══════════════════════════════════════════════════════════════════════════

  test "applies both visibility and team filters" do
    # Visible: alice, bob, charlie. Team: alice, charlie.
    # Result: alice, charlie (intersection of visibility and team)
    json = MetricsResponseSerializer.new(
      @sprint,
      visible_logins: %w[alice bob charlie],
      team_logins: %w[alice charlie]
    ).as_json

    names = json[:developers].map { |d| d[:developer] }
    assert_equal %w[alice charlie], names.sort
  end

  test "handles empty result when no developers match filters" do
    json = MetricsResponseSerializer.new(@sprint, team_logins: %w[nobody]).as_json

    assert_equal 0, json[:developers].size
    assert_equal 0.0, json[:summary][:avg_dxi_score]
    assert_equal 0, json[:summary][:total_commits]
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # filter_meta
  # ═══════════════════════════════════════════════════════════════════════════

  test "includes filter_meta when filters are active" do
    json = MetricsResponseSerializer.new(@sprint, visible_logins: %w[alice bob]).as_json

    assert json.key?(:filter_meta)
    assert_equal 3, json[:filter_meta][:total_developers]
    assert_equal 2, json[:filter_meta][:showing_developers]
  end

  test "includes team_name in filter_meta when team filtering" do
    json = MetricsResponseSerializer.new(
      @sprint,
      team_logins: %w[alice],
      team_name: "Backend"
    ).as_json

    assert_equal "Backend", json[:filter_meta][:team_name]
  end

  private

  def developer_data(name, commits: 5, dxi_score: 60.0)
    {
      "developer" => name,
      "commits" => commits,
      "prs_opened" => 2,
      "prs_merged" => 2,
      "reviews_given" => 3,
      "lines_added" => 100,
      "lines_deleted" => 30,
      "dxi_score" => dxi_score,
      "dimension_scores" => {
        "review_turnaround" => 85.0,
        "cycle_time" => 75.0,
        "pr_size" => 90.0,
        "review_coverage" => 30.0,
        "commit_frequency" => 25.0
      }
    }
  end
end
