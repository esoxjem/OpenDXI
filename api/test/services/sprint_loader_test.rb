# frozen_string_literal: true

require "test_helper"

class SprintLoaderTest < ActiveSupport::TestCase
  # ═══════════════════════════════════════════════════════════════════════════
  # Setup
  # ═══════════════════════════════════════════════════════════════════════════

  setup do
    @start_date = Date.new(2026, 1, 7)
    @end_date = Date.new(2026, 1, 20)
    @mock_data = {
      "team_metrics" => { "total_prs" => 10 },
      "developers" => []
    }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Mock Fetcher for Testing
  # ═══════════════════════════════════════════════════════════════════════════

  class MockFetcher
    attr_reader :fetch_count

    def initialize(data)
      @data = data
      @fetch_count = 0
    end

    def fetch_sprint_data(_start_date, _end_date)
      @fetch_count += 1
      @data
    end
  end

  class SlowMockFetcher
    attr_reader :fetch_count

    def initialize(data, delay: 0.1)
      @data = data
      @delay = delay
      @fetch_count = 0
    end

    def fetch_sprint_data(_start_date, _end_date)
      @fetch_count += 1
      sleep(@delay)
      @data
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Basic Loading Tests
  # ═══════════════════════════════════════════════════════════════════════════

  test "load creates new sprint when not cached" do
    fetcher = MockFetcher.new(@mock_data)
    loader = SprintLoader.new(fetcher: fetcher)

    sprint = loader.load(@start_date, @end_date)

    assert sprint.persisted?
    assert_equal @start_date, sprint.start_date
    assert_equal @end_date, sprint.end_date
    assert_equal @mock_data, sprint.data
    assert_equal 1, fetcher.fetch_count
  end

  test "load returns cached sprint without fetching" do
    # Pre-create a cached sprint
    existing = Sprint.create!(
      start_date: @start_date,
      end_date: @end_date,
      data: { "cached" => true }
    )

    fetcher = MockFetcher.new(@mock_data)
    loader = SprintLoader.new(fetcher: fetcher)

    sprint = loader.load(@start_date, @end_date)

    assert_equal existing.id, sprint.id
    assert_equal({ "cached" => true }, sprint.data)
    assert_equal 0, fetcher.fetch_count, "Should not fetch when cached"
  end

  test "load accepts string dates" do
    fetcher = MockFetcher.new(@mock_data)
    loader = SprintLoader.new(fetcher: fetcher)

    sprint = loader.load("2026-01-07", "2026-01-20")

    assert sprint.persisted?
    assert_equal @start_date, sprint.start_date
    assert_equal @end_date, sprint.end_date
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Force Refresh Tests
  # ═══════════════════════════════════════════════════════════════════════════

  test "load with force: true refetches and updates existing sprint" do
    # Pre-create a cached sprint
    existing = Sprint.create!(
      start_date: @start_date,
      end_date: @end_date,
      data: { "old" => "data" }
    )

    fetcher = MockFetcher.new(@mock_data)
    loader = SprintLoader.new(fetcher: fetcher)

    sprint = loader.load(@start_date, @end_date, force: true)

    assert_equal existing.id, sprint.id
    assert_equal @mock_data, sprint.data
    assert_equal 1, fetcher.fetch_count, "Should fetch when force: true"
  end

  test "load with force: true creates new sprint if none exists" do
    fetcher = MockFetcher.new(@mock_data)
    loader = SprintLoader.new(fetcher: fetcher)

    sprint = loader.load(@start_date, @end_date, force: true)

    assert sprint.persisted?
    assert_equal @mock_data, sprint.data
    assert_equal 1, fetcher.fetch_count
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Race Condition Tests
  # ═══════════════════════════════════════════════════════════════════════════

  test "handles concurrent creation gracefully via RecordNotUnique" do
    # Simulate race condition by creating sprint after first check but before insert
    call_count = 0
    fetcher = Object.new
    fetcher.define_singleton_method(:fetch_sprint_data) do |_s, _e|
      call_count += 1
      # Simulate another request creating the sprint during fetch
      Sprint.find_or_create_by!(
        start_date: Date.new(2026, 1, 7),
        end_date: Date.new(2026, 1, 20)
      ) { |s| s.data = { "created_by" => "concurrent" } }
      { "team_metrics" => {} }
    end

    loader = SprintLoader.new(fetcher: fetcher)

    # This should handle RecordNotUnique and return the existing sprint
    sprint = loader.load(@start_date, @end_date)

    assert sprint.persisted?
    assert_equal 1, Sprint.where(start_date: @start_date, end_date: @end_date).count
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Transaction Scope Tests (Critical for SQLite)
  # ═══════════════════════════════════════════════════════════════════════════

  test "fetch happens outside loader transaction to avoid long locks" do
    # This test verifies the fix for SQLite3::BusyException
    # The fetch should NOT be wrapped in SprintLoader's transaction
    #
    # Note: Rails test transactions add 1 to open_transactions, so we compare
    # against the baseline, not zero.

    baseline_transactions = Sprint.connection.open_transactions
    transactions_during_fetch = nil

    fetcher = Object.new
    fetcher.define_singleton_method(:fetch_sprint_data) do |_s, _e|
      # Capture transaction count during fetch
      transactions_during_fetch = Sprint.connection.open_transactions
      { "team_metrics" => {} }
    end

    loader = SprintLoader.new(fetcher: fetcher)
    loader.load(@start_date, @end_date)

    assert_equal baseline_transactions, transactions_during_fetch,
      "Fetch should happen at same transaction level as caller (not inside additional transaction)"
  end

  test "database write happens inside a transaction" do
    # Note: Rails test transactions add 1 to open_transactions baseline
    baseline_transactions = Sprint.connection.open_transactions
    transactions_during_write = nil

    # Use callback to check transaction state during save
    Sprint.class_eval do
      before_save do
        @transactions_during_write = Sprint.connection.open_transactions
      end
    end

    fetcher = MockFetcher.new(@mock_data)
    loader = SprintLoader.new(fetcher: fetcher)
    sprint = loader.load(@start_date, @end_date)

    transactions_during_write = sprint.instance_variable_get(:@transactions_during_write)
    assert transactions_during_write > baseline_transactions,
      "Database write should happen inside an additional transaction"
  ensure
    Sprint.class_eval { reset_callbacks(:save) }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Default Fetcher Tests
  # ═══════════════════════════════════════════════════════════════════════════

  test "uses GithubService as default fetcher" do
    loader = SprintLoader.new
    assert_equal GithubService, loader.instance_variable_get(:@fetcher)
  end
end
