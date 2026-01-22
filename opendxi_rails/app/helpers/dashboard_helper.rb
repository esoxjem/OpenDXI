# frozen_string_literal: true

module DashboardHelper
  # Format hours into human-readable string
  def format_hours(hours)
    return "—" if hours.nil?
    hours < 1 ? "#{(hours * 60).round}m" : "#{hours.round(1)}h"
  end

  # CSS class for DXI score based on threshold
  def dxi_score_class(score)
    return "text-gray-500" if score.nil?

    case score
    when 70.. then "text-green-600"
    when 50..70 then "text-yellow-600"
    else "text-red-600"
    end
  end

  # Background class for DXI score card
  def dxi_score_bg_class(score)
    return "bg-gray-100" if score.nil?

    case score
    when 70.. then "bg-green-50 border-green-200"
    when 50..70 then "bg-yellow-50 border-yellow-200"
    else "bg-red-50 border-red-200"
    end
  end

  # Human-readable label for DXI score
  def dxi_score_label(score)
    return "No data" if score.nil?

    case score
    when 70.. then "Good"
    when 50..70 then "Moderate"
    else "Needs Improvement"
    end
  end

  # Trend indicator with arrow
  def trend_indicator(current, previous)
    return content_tag(:span, "—", class: "text-gray-400 text-sm") if previous.nil? || previous.zero?

    change = ((current - previous) / previous.to_f * 100).round(1)
    if change > 0
      content_tag(:span, class: "text-green-600 text-sm inline-flex items-center") do
        concat(content_tag(:span, "▲", class: "mr-0.5"))
        concat("#{change}%")
      end
    elsif change < 0
      content_tag(:span, class: "text-red-600 text-sm inline-flex items-center") do
        concat(content_tag(:span, "▼", class: "mr-0.5"))
        concat("#{change.abs}%")
      end
    else
      content_tag(:span, "—", class: "text-gray-400 text-sm")
    end
  end

  # Format large numbers with delimiter
  def format_number(n)
    return "—" if n.nil?
    number_with_delimiter(n)
  end

  # Sort link for leaderboard table headers
  def sort_link(label, field, current_sort, current_dir, sprint)
    new_dir = (current_sort.to_s == field.to_s && current_dir == "desc") ? "asc" : "desc"
    is_active = current_sort.to_s == field.to_s

    arrow = if is_active
              current_dir == "desc" ? " ↓" : " ↑"
    else
              ""
    end

    link_to "#{label}#{arrow}",
            dashboard_path(sprint: sprint.date_range_param, sort: field, dir: new_dir, view: "developers"),
            class: "hover:text-blue-600 #{is_active ? 'font-semibold text-blue-600' : ''}",
            data: { turbo_frame: "leaderboard" }
  end

  # Sort developers based on params
  def sorted_developers(sprint, sort_by, sort_dir)
    developers = sprint.developers
    sort_by ||= "dxi_score"
    sort_dir ||= "desc"

    sorted = developers.sort_by do |dev|
      value = dev[sort_by]
      value = 0 if value.nil?
      sort_dir == "asc" ? value : -value.to_f
    end

    # For numeric sorts in asc, keep nil at end
    if sort_dir == "asc"
      sorted = sorted.sort_by { |dev| dev[sort_by].nil? ? 1 : 0 }
    end

    sorted
  end

  # Dimension score as percentage bar width
  def dimension_bar_width(score)
    return 0 if score.nil?
    [ score.to_f, 100 ].min
  end

  # Dimension score color class
  def dimension_color_class(score)
    return "bg-gray-300" if score.nil?

    case score
    when 70.. then "bg-green-500"
    when 50..70 then "bg-yellow-500"
    else "bg-red-500"
    end
  end

  # Human-readable dimension name
  def dimension_label(key)
    {
      "review_turnaround" => "Review Speed",
      "cycle_time" => "Cycle Time",
      "pr_size" => "PR Size",
      "review_coverage" => "Review Coverage",
      "commit_frequency" => "Commit Frequency"
    }[key.to_s] || key.to_s.humanize
  end
end
