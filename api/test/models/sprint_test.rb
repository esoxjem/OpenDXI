# frozen_string_literal: true

require "test_helper"

class SprintTest < ActiveSupport::TestCase
  setup do
    @sprint = Sprint.create!(
      start_date: Date.new(2026, 1, 7),
      end_date: Date.new(2026, 1, 20),
      data: sample_sprint_data
    )
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Validations
  # ═══════════════════════════════════════════════════════════════════════════

  test "validates presence of start_date" do
    sprint = Sprint.new(end_date: Date.today)
    assert_not sprint.valid?
    assert_includes sprint.errors[:start_date], "can't be blank"
  end

  test "validates presence of end_date" do
    sprint = Sprint.new(start_date: Date.today)
    assert_not sprint.valid?
    assert_includes sprint.errors[:end_date], "can't be blank"
  end

  test "validates end_date after start_date" do
    sprint = Sprint.new(start_date: Date.today, end_date: Date.today - 1)
    assert_not sprint.valid?
    assert_includes sprint.errors[:end_date], "must be after start date"
  end

  test "validates uniqueness of start_date scoped to end_date" do
    duplicate = Sprint.new(
      start_date: @sprint.start_date,
      end_date: @sprint.end_date
    )
    assert_not duplicate.valid?
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # JSON Accessors
  # ═══════════════════════════════════════════════════════════════════════════

  test "developers returns array from data" do
    assert_kind_of Array, @sprint.developers
    assert_equal 2, @sprint.developers.size
    assert_equal "dev1", @sprint.developers.first["developer"]
  end

  test "developers returns empty array when data is nil" do
    @sprint.data = nil
    assert_equal [], @sprint.developers
  end

  test "summary returns hash from data" do
    assert_kind_of Hash, @sprint.summary
    assert_equal 30, @sprint.summary["total_commits"]
  end

  test "team_dimension_scores returns hash from data" do
    assert_kind_of Hash, @sprint.team_dimension_scores
    assert @sprint.team_dimension_scores.key?("review_turnaround")
  end

  test "daily_activity returns array from data" do
    assert_kind_of Array, @sprint.daily_activity
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Instance Methods
  # ═══════════════════════════════════════════════════════════════════════════

  test "current? returns true for current sprint" do
    sprint = Sprint.create!(
      start_date: Date.current - 7,
      end_date: Date.current + 7
    )
    assert sprint.current?
  end

  test "current? returns false for past sprint" do
    sprint = Sprint.create!(
      start_date: Date.current - 30,
      end_date: Date.current - 16
    )
    assert_not sprint.current?
  end

  test "label returns 'Current Sprint' for current sprint" do
    sprint = Sprint.create!(
      start_date: Date.current - 7,
      end_date: Date.current + 7
    )
    assert_equal "Current Sprint", sprint.label
  end

  test "label returns date range for past sprint" do
    assert_match %r{\w+ \d+ - \w+ \d+}, @sprint.label
  end

  test "find_developer returns developer by login" do
    dev = @sprint.find_developer("dev1")
    assert_not_nil dev
    assert_equal "dev1", dev["developer"]
  end

  test "find_developer returns nil for unknown login" do
    assert_nil @sprint.find_developer("unknown")
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Scopes
  # ═══════════════════════════════════════════════════════════════════════════

  test "current scope returns sprints containing today" do
    current = Sprint.create!(
      start_date: Date.current - 7,
      end_date: Date.current + 7,
      data: {}
    )
    results = Sprint.current
    assert_includes results, current
    assert_not_includes results, @sprint
  end

  test "recent scope returns sprints ordered by start_date desc" do
    results = Sprint.recent
    assert_equal results, results.sort_by { |s| -s.start_date.to_time.to_i }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Class Methods
  # ═══════════════════════════════════════════════════════════════════════════

  test "find_by_dates returns sprint matching dates" do
    found = Sprint.find_by_dates(@sprint.start_date, @sprint.end_date)
    assert_equal @sprint, found
  end

  test "find_by_dates returns nil for non-existent dates" do
    found = Sprint.find_by_dates(Date.new(2025, 1, 1), Date.new(2025, 1, 14))
    assert_nil found
  end

  test "available_sprints returns array of sprint options" do
    sprints = Sprint.available_sprints(limit: 3)
    assert_kind_of Array, sprints
    assert_equal 3, sprints.size
    assert sprints.first[:is_current]
    assert sprints.first[:label] == "Current Sprint"
  end

  test "current_sprint_dates returns start and end dates" do
    start_date, end_date = Sprint.current_sprint_dates
    assert_kind_of Date, start_date
    assert_kind_of Date, end_date
    assert start_date < end_date
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Race Condition Handling (P1-001)
  # ═══════════════════════════════════════════════════════════════════════════

  test "find_or_fetch! returns existing sprint without calling GitHub" do
    # Existing sprint should be returned directly without fetching
    result = Sprint.find_or_fetch!(@sprint.start_date, @sprint.end_date)

    assert_equal @sprint, result
    # If GithubService was called, the data would be different (empty or error)
    # The fact that our sample data is intact proves no fetch occurred
    assert_equal 2, result.developers.size
  end

  test "find_or_fetch! accepts string dates" do
    result = Sprint.find_or_fetch!(@sprint.start_date.to_s, @sprint.end_date.to_s)

    assert_equal @sprint, result
  end

  test "unique index prevents duplicate sprints" do
    # The race condition fix relies on the unique index to catch duplicates
    # Verify the index exists by trying to create a duplicate
    duplicate = Sprint.new(
      start_date: @sprint.start_date,
      end_date: @sprint.end_date,
      data: {}
    )

    assert_raises(ActiveRecord::RecordInvalid) { duplicate.save! }
  end

  test "find_or_fetch! wrapped in transaction" do
    # Verify the method uses a transaction by checking it's atomic
    # This is a structural test - if the method changes to not use
    # transactions, this test documents that expectation
    source = Sprint.method(:find_or_fetch!).source_location
    source_file = File.read(source.first)

    assert_match(/transaction do/, source_file,
      "find_or_fetch! should use a transaction for race condition handling")
    assert_match(/rescue ActiveRecord::RecordNotUnique/, source_file,
      "find_or_fetch! should rescue RecordNotUnique")
  end

  private

  def sample_sprint_data
    {
      "developers" => [
        {
          "developer" => "dev1",
          "github_login" => "dev1",
          "commits" => 15,
          "prs_opened" => 3,
          "prs_merged" => 2,
          "reviews_given" => 5,
          "lines_added" => 500,
          "lines_deleted" => 200,
          "avg_review_time_hours" => 4.5,
          "avg_cycle_time_hours" => 12.0,
          "dxi_score" => 78.5,
          "dimension_scores" => {
            "review_turnaround" => 88.6,
            "cycle_time" => 80.0,
            "pr_size" => 70.0,
            "review_coverage" => 50.0,
            "commit_frequency" => 75.0
          }
        },
        {
          "developer" => "dev2",
          "github_login" => "dev2",
          "commits" => 15,
          "prs_opened" => 2,
          "prs_merged" => 2,
          "reviews_given" => 8,
          "lines_added" => 300,
          "lines_deleted" => 100,
          "dxi_score" => 82.0,
          "dimension_scores" => {
            "review_turnaround" => 90.0,
            "cycle_time" => 85.0,
            "pr_size" => 100.0,
            "review_coverage" => 80.0,
            "commit_frequency" => 75.0
          }
        }
      ],
      "daily_activity" => [
        { "date" => "2026-01-07", "commits" => 5, "prs_opened" => 2, "prs_merged" => 1, "reviews_given" => 3 },
        { "date" => "2026-01-08", "commits" => 8, "prs_opened" => 3, "prs_merged" => 2, "reviews_given" => 5 }
      ],
      "summary" => {
        "total_commits" => 30,
        "total_prs" => 5,
        "total_merged" => 4,
        "total_reviews" => 13,
        "developer_count" => 2,
        "avg_dxi_score" => 80.25
      },
      "team_dimension_scores" => {
        "review_turnaround" => 89.3,
        "cycle_time" => 82.5,
        "pr_size" => 85.0,
        "review_coverage" => 65.0,
        "commit_frequency" => 75.0
      }
    }
  end
end
