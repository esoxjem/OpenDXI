# frozen_string_literal: true

require "digest"

# Sprint model - stores sprint metrics with JSON blob for flexibility
#
# The data column contains all developer metrics, daily activity, and scores.
# This matches the access pattern (always load full sprint) and simplifies
# the codebase vs. normalized tables.
class Sprint < ApplicationRecord
  validates :start_date, :end_date, presence: true
  validates :start_date, uniqueness: { scope: :end_date }
  validate :end_date_after_start_date
  validate :validate_data_structure

  scope :current, -> { where("start_date <= ? AND end_date >= ?", Date.current, Date.current) }
  scope :by_date, ->(date) { where("start_date <= ? AND end_date >= ?", date, date) }
  scope :recent, -> { order(start_date: :desc).limit(10) }

  class << self
    def find_by_dates(start_date, end_date)
      find_by(start_date: start_date, end_date: end_date)
    end

    # Find or fetch sprint data, optionally forcing a refresh.
    #
    # Delegates to SprintLoader for dependency-injected data fetching.
    # This maintains the existing API while decoupling the model from GithubService.
    #
    # @param start_date [Date, String] Sprint start date
    # @param end_date [Date, String] Sprint end date
    # @param force [Boolean] When true, refetch data even if cached
    # @return [Sprint] The loaded or created Sprint record
    def find_or_fetch!(start_date, end_date, force: false)
      SprintLoader.new.load(start_date, end_date, force: force)
    end

    # Calculate current sprint dates based on configuration
    def current_sprint_dates
      config = Rails.application.config.opendxi
      start_anchor = config.sprint_start_date
      duration = config.sprint_duration_days
      today = Date.current

      days_since_start = (today - start_anchor).to_i
      current_sprint_num = days_since_start / duration
      sprint_start = start_anchor + (current_sprint_num * duration).days
      sprint_end = sprint_start + (duration - 1).days

      [ sprint_start, sprint_end ]
    end

    # Get list of available sprints for dropdown selector
    def available_sprints(limit: 6)
      config = Rails.application.config.opendxi
      start_anchor = config.sprint_start_date
      duration = config.sprint_duration_days
      today = Date.current

      days_since_start = (today - start_anchor).to_i
      current_sprint_num = days_since_start / duration

      (0...limit).map do |i|
        sprint_num = current_sprint_num - i
        sprint_start = start_anchor + (sprint_num * duration).days
        sprint_end = sprint_start + (duration - 1).days

        {
          label: i.zero? ? "Current Sprint" : "#{sprint_start.strftime('%b %d')} - #{sprint_end.strftime('%b %d')}",
          value: "#{sprint_start}|#{sprint_end}",
          start_date: sprint_start,
          end_date: sprint_end,
          is_current: i.zero?
        }
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # JSON Data Accessors
  # ═══════════════════════════════════════════════════════════════════════════

  def developers
    data&.dig("developers") || []
  end

  def daily_activity
    data&.dig("daily_activity") || []
  end

  def summary
    data&.dig("summary") || {}
  end

  def team_dimension_scores
    data&.dig("team_dimension_scores") || {}
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Instance Methods
  # ═══════════════════════════════════════════════════════════════════════════

  def current?
    start_date <= Date.current && end_date >= Date.current
  end

  def label
    current? ? "Current Sprint" : "#{start_date.strftime('%b %d')} - #{end_date.strftime('%b %d')}"
  end

  def date_range_param
    "#{start_date}|#{end_date}"
  end

  # Generate content-based ETag for HTTP caching
  #
  # Creates a unique cache key based on:
  # - Actual data content (MD5 hash of sorted data)
  # - Updated timestamp
  #
  # This ensures ETags change if:
  # - Data content changes (even if timestamp hasn't updated)
  # - Record is updated
  #
  # ETag format: "#{id}-#{data_hash}-#{updated_timestamp}"
  # Example: "123-5d41402abc4b2a76b9719d911017c592-1672531200"
  def generate_cache_key
    return unless id
    if data.present?
      data_hash = Digest::MD5.hexdigest(JSON.generate(data.to_h.sort.to_s))
      "#{id}-#{data_hash}-#{updated_at.to_i}"
    else
      "#{id}-empty-#{updated_at.to_i}"
    end
  end

  # Find a specific developer by login
  def find_developer(login)
    developers.find { |d| d["developer"] == login || d["github_login"] == login }
  end

  # Recalculate DXI scores (useful after algorithm changes)
  def recalculate_scores!
    return unless data.present?

    developers_with_scores = developers.map do |dev|
      scores = DxiCalculator.dimension_scores(dev)
      dev.merge(
        "dxi_score" => DxiCalculator.composite_score(scores),
        "dimension_scores" => scores.transform_keys(&:to_s)
      )
    end

    self.data = data.merge(
      "developers" => developers_with_scores,
      "team_dimension_scores" => DxiCalculator.team_dimension_scores(developers_with_scores).transform_keys(&:to_s),
      "summary" => build_summary(developers_with_scores)
    )
    save!
  end

  private

  def end_date_after_start_date
    return unless start_date && end_date
    errors.add(:end_date, "must be after start date") if end_date < start_date
  end

  # Validates the JSON data structure to catch corruption early.
  # This ensures data integrity and provides clear error messages.
  def validate_data_structure
    return if data.blank?

    unless data.is_a?(Hash)
      errors.add(:data, "must be a hash")
      return
    end

    validate_array_field("developers")
    validate_array_field("daily_activity")
    validate_hash_field("summary")
    validate_hash_field("team_dimension_scores")
  end

  def validate_array_field(key)
    value = data[key]
    return if value.nil?
    errors.add(:data, "#{key} must be an array") unless value.is_a?(Array)
  end

  def validate_hash_field(key)
    value = data[key]
    return if value.nil?
    errors.add(:data, "#{key} must be a hash") unless value.is_a?(Hash)
  end

  def build_summary(devs)
    {
      "total_commits" => devs.sum { |d| d["commits"] || 0 },
      "total_prs" => devs.sum { |d| d["prs_opened"] || 0 },
      "total_merged" => devs.sum { |d| d["prs_merged"] || 0 },
      "total_reviews" => devs.sum { |d| d["reviews_given"] || 0 },
      "developer_count" => devs.size,
      "avg_dxi_score" => devs.any? ? (devs.sum { |d| d["dxi_score"] || 0 } / devs.size.to_f).round(1) : 0
    }
  end
end
