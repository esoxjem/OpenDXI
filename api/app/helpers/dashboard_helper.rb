# frozen_string_literal: true

module DashboardHelper
  # Format hours into human-readable string
  def format_hours(hours)
    return "--" if hours.nil?

    hours = hours.to_f
    return "<1h" if hours < 1

    if hours < 24
      "#{hours.round(1)}h"
    else
      days = (hours / 24).floor
      remaining_hours = (hours % 24).round
      remaining_hours > 0 ? "#{days}d #{remaining_hours}h" : "#{days}d"
    end
  end

  # CSS class for DXI score badge
  def score_badge_class(score)
    return "score-needs-improvement" if score.nil?

    case score.to_f
    when 70..Float::INFINITY then "score-good"
    when 50...70 then "score-moderate"
    else "score-needs-improvement"
    end
  end

  # CSS class for score text color
  def score_text_class(score)
    return "text-muted-foreground" if score.nil?

    case score.to_f
    when 70..Float::INFINITY then "text-success"
    when 50...70 then "text-warning"
    else "text-destructive"
    end
  end

  # Human-readable label for DXI score
  def score_label(score)
    return "No data" if score.nil?

    case score.to_f
    when 70..Float::INFINITY then "Good"
    when 50...70 then "Moderate"
    else "Needs Improvement"
    end
  end

  # Format large numbers with delimiter
  def format_number(n)
    return "--" if n.nil?
    number_with_delimiter(n.to_i)
  end

  # Get trend indicator hash
  def trend_indicator(current, previous, invert: false)
    return nil if current.nil? || previous.nil? || previous.to_f.zero?

    delta = current.to_f - previous.to_f
    positive = invert ? delta < 0 : delta > 0

    {
      arrow: positive ? "▲" : "▼",
      value: delta.abs < 10 ? delta.abs.round(1) : delta.abs.round,
      class: positive ? "trend-up" : "trend-down",
      sign: delta > 0 ? "+" : ""
    }
  end

  # Dimension score bar width (0-100%)
  def dimension_bar_width(score)
    return 0 if score.nil?
    [score.to_f, 100].min
  end

  # CSS class for dimension score bar
  def dimension_bar_class(score)
    return "bg-muted" if score.nil?

    case score.to_f
    when 70..Float::INFINITY then "bg-primary"
    when 50...70 then "bg-warning"
    else "bg-destructive"
    end
  end

  # Human-readable dimension name
  def dimension_label(key)
    {
      "review_speed" => "Review Speed",
      "review_turnaround" => "Review Speed",
      "cycle_time" => "Cycle Time",
      "pr_size" => "PR Size",
      "review_coverage" => "Review Coverage",
      "commit_frequency" => "Commit Frequency"
    }[key.to_s] || key.to_s.humanize
  end

  # GitHub org name from config
  def github_org
    Rails.application.config.opendxi[:github_org] || "Organization"
  end

  # Sort developers based on params
  def sorted_developers(developers, sort_by, sort_dir)
    return [] if developers.blank?

    sort_by ||= :dxi_score
    sort_dir ||= "desc"

    sorted = developers.sort_by do |dev|
      value = dev[sort_by.to_sym] || dev[sort_by.to_s]
      value = 0 if value.nil?
      sort_dir == "asc" ? value.to_f : -value.to_f
    end

    sorted
  end
end
