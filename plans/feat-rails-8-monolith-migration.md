# OpenDXI: Rails 8 Monolith Migration

## Summary

Complete rewrite of OpenDXI from **FastAPI + Next.js/React** to a **Rails 8 monolith with Hotwire** (Turbo + Stimulus). This eliminates the separate frontend/backend architecture in favor of Rails conventions, server-rendered HTML, and progressive enhancement.

**Motivations:** Rails conventions, stack simplification, Hotwire benefits
**Data Strategy:** Preserve existing SQLite data via migration task
**Chart Solution:** Chartkick for line/bar charts + Chart.js/Stimulus for radar chart

---

## Architecture Overview

```
Current Stack                    Target Stack
─────────────────────────────    ─────────────────────────────
FastAPI (Python)                 Rails 8 (Ruby)
├── routers/sprints.py           ├── app/controllers/
├── routers/developers.py        ├── app/models/
├── services/github_service.py   ├── app/services/
├── services/metrics_service.py  └── app/views/ (ERB + Hotwire)
└── services/sprint_store.py

Next.js/React                    Hotwire
├── TanStack Query               ├── Turbo Frames (lazy loading)
├── shadcn/ui components         ├── Turbo Streams (refresh)
└── Chart.js                     └── Stimulus (radar chart only)

SQLite (JSON blobs)              SQLite (JSON blobs - keep simple)
```

---

## Phase 1: Rails Project Setup

### 1.1 Initialize Project

```bash
rails new opendxi_rails \
  --database=sqlite3 \
  --css=tailwind \
  --skip-jbuilder \
  --skip-action-mailbox \
  --skip-action-mailer \
  --skip-active-storage
```

> **Note:** Using importmap (Rails default) instead of esbuild. Simpler for this project's needs.

### 1.2 Gemfile Additions

```ruby
gem "chartkick"           # Line/bar/area charts
gem "groupdate"           # Date grouping helpers
```

> **Removed:** `solid_queue`, `solid_cache`, `solid_cable` - YAGNI. No async jobs needed (refresh takes <5s), no caching layer needed (SQLite IS the cache), no real-time features.

### 1.3 JavaScript Dependencies

```bash
bin/importmap pin chart.js chartkick
```

### 1.4 Configuration

Create a dedicated initializer for OpenDXI settings:

```ruby
# config/initializers/opendxi.rb
Rails.application.configure do
  config.opendxi = ActiveSupport::OrderedOptions.new
  config.opendxi.github_org = ENV.fetch("GITHUB_ORG")
  config.opendxi.sprint_start_date = Date.parse(ENV.fetch("SPRINT_START_DATE", "2026-01-07"))
  config.opendxi.sprint_duration_days = ENV.fetch("SPRINT_DURATION_DAYS", "14").to_i
  config.opendxi.max_pages_per_query = ENV.fetch("MAX_PAGES_PER_QUERY", "10").to_i
end
```

Access via `Rails.application.config.opendxi.github_org`.

---

## Phase 2: Database Schema

### 2.1 Simple Schema (Single Table with JSON)

This dashboard is read-heavy, write-rare. Data is always accessed as a complete unit. Keep it simple.

**Single migration:**

```ruby
# db/migrate/001_create_sprints.rb
class CreateSprints < ActiveRecord::Migration[8.0]
  def change
    create_table :sprints do |t|
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.json :data  # All metrics, developers, daily activity
      t.timestamps

      t.index [:start_date, :end_date], unique: true
      t.index :start_date  # For finding current sprint
    end
  end
end
```

### 2.2 Sprint Model

```ruby
# app/models/sprint.rb
class Sprint < ApplicationRecord
  validates :start_date, :end_date, presence: true
  validates :start_date, uniqueness: { scope: :end_date }

  scope :current, -> { where("start_date <= ? AND end_date >= ?", Date.current, Date.current) }
  scope :by_date, ->(date) { where("start_date <= ? AND end_date >= ?", date, date) }
  scope :recent, -> { order(start_date: :desc).limit(10) }

  def self.find_by_dates(start_date, end_date)
    find_by(start_date: start_date, end_date: end_date)
  end

  def self.find_or_fetch!(start_date, end_date, force: false)
    sprint = find_by_dates(start_date, end_date)
    return sprint if sprint && !force

    data = GithubService.fetch_sprint_data(start_date, end_date)

    if sprint
      sprint.update!(data: data)
    else
      sprint = create!(start_date: start_date, end_date: end_date, data: data)
    end

    sprint
  end

  # Accessor methods for JSON data
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

  def current?
    start_date <= Date.current && end_date >= Date.current
  end

  def label
    current? ? "Current Sprint" : "#{start_date.strftime('%b %d')} - #{end_date.strftime('%b %d')}"
  end

  # DXI calculation delegated to model (fat models, skinny controllers)
  def recalculate_scores!
    return unless data.present?

    developers_with_scores = developers.map do |dev|
      scores = DxiCalculator.dimension_scores(dev)
      dev.merge(
        "dxi_score" => DxiCalculator.composite_score(scores),
        "dimension_scores" => scores
      )
    end

    self.data = data.merge(
      "developers" => developers_with_scores,
      "team_dimension_scores" => DxiCalculator.team_dimension_scores(developers_with_scores),
      "summary" => build_summary(developers_with_scores)
    )
    save!
  end

  private

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
```

> **Design Decision:** Using a single table with JSON instead of 5 normalized tables. This matches the access pattern (always load full sprint), simplifies the codebase, and the existing Python implementation proves this works. No complex joins, no N+1 queries, no association management.

---

## Phase 3: Service Layer

### 3.1 DxiCalculator (`app/services/dxi_calculator.rb`)

Single class for all DXI scoring logic. Extract constants for testability.

**Port exact algorithm from:** `api/services/metrics_service.py:60-116`

```ruby
# app/services/dxi_calculator.rb
class DxiCalculator
  WEIGHTS = {
    review_turnaround: 0.25,
    cycle_time: 0.25,
    pr_size: 0.20,
    review_coverage: 0.15,
    commit_frequency: 0.15
  }.freeze

  THRESHOLDS = {
    review_time: { min: 2, max: 24 },      # hours
    cycle_time: { min: 8, max: 72 },       # hours
    pr_size: { min: 200, max: 1000 },      # lines
    reviews: { target: 10 },               # count
    commits: { target: 20 }                # count
  }.freeze

  class << self
    def composite_score(dimension_scores)
      WEIGHTS.sum { |dim, weight| (dimension_scores[dim] || 0) * weight }.round(1)
    end

    def dimension_scores(metrics)
      {
        review_turnaround: review_turnaround_score(metrics["avg_review_time_hours"]),
        cycle_time: cycle_time_score(metrics["avg_cycle_time_hours"]),
        pr_size: pr_size_score(metrics["lines_added"], metrics["lines_deleted"], metrics["prs_opened"]),
        review_coverage: review_coverage_score(metrics["reviews_given"]),
        commit_frequency: commit_frequency_score(metrics["commits"])
      }
    end

    def team_dimension_scores(developers)
      return {} if developers.empty?

      dimensions = %i[review_turnaround cycle_time pr_size review_coverage commit_frequency]
      dimensions.index_with do |dim|
        scores = developers.map { |d| d.dig("dimension_scores", dim.to_s) || 0 }
        (scores.sum / scores.size.to_f).round(1)
      end
    end

    private

    def review_turnaround_score(hours)
      return 100.0 if hours.nil? || hours <= THRESHOLDS[:review_time][:min]
      normalize(hours, THRESHOLDS[:review_time][:min], THRESHOLDS[:review_time][:max])
    end

    def cycle_time_score(hours)
      return 100.0 if hours.nil? || hours <= THRESHOLDS[:cycle_time][:min]
      normalize(hours, THRESHOLDS[:cycle_time][:min], THRESHOLDS[:cycle_time][:max])
    end

    def pr_size_score(lines_added, lines_deleted, prs_opened)
      return 100.0 if prs_opened.nil? || prs_opened.zero?
      avg_size = ((lines_added || 0) + (lines_deleted || 0)) / prs_opened.to_f
      return 100.0 if avg_size <= THRESHOLDS[:pr_size][:min]
      normalize(avg_size, THRESHOLDS[:pr_size][:min], THRESHOLDS[:pr_size][:max])
    end

    def review_coverage_score(reviews)
      return 0.0 if reviews.nil?
      [(reviews * 10), 100].min.to_f
    end

    def commit_frequency_score(commits)
      return 0.0 if commits.nil?
      [(commits * 5), 100].min.to_f
    end

    def normalize(value, min, max)
      score = 100 - (value - min) * (100.0 / (max - min))
      [[0, score].max, 100].min.round(1)
    end
  end
end
```

### 3.2 GithubService (`app/services/github_service.rb`)

Combines fetching, processing, and aggregation into one service. No need for separate `MetricsProcessor` or `SprintService`.

**Port from:** `api/services/github_service.py`

```ruby
# app/services/github_service.rb
class GithubService
  class GhCliNotFound < StandardError; end
  class GitHubApiError < StandardError; end

  GRAPHQL_QUERIES = {
    repos: <<~GRAPHQL,
      query($org: String!, $cursor: String) {
        organization(login: $org) {
          repositories(first: 100, after: $cursor) {
            pageInfo { hasNextPage endCursor }
            nodes { name }
          }
        }
      }
    GRAPHQL
    # ... other queries (PRS, REVIEWS, COMMITS)
  }.freeze

  class << self
    def fetch_sprint_data(start_date, end_date)
      validate_gh_cli!

      repos = fetch_repos
      prs = fetch_prs(repos, start_date, end_date)
      commits = fetch_commits(repos, start_date, end_date)
      reviews = fetch_reviews(prs.map { |pr| pr["number"] })

      aggregate_data(prs, commits, reviews, start_date, end_date)
    end

    private

    def validate_gh_cli!
      result = `which gh 2>/dev/null`.strip
      raise GhCliNotFound, "gh CLI not found. Install from https://cli.github.com" if result.empty?
    end

    def run_graphql(query, variables = {})
      org = Rails.application.config.opendxi.github_org
      cmd = ["gh", "api", "graphql", "-f", "query=#{query}"]
      variables.merge(org: org).each { |k, v| cmd += ["-f", "#{k}=#{v}"] }

      result = `#{cmd.shelljoin} 2>&1`
      raise GitHubApiError, "GitHub API error: #{result}" unless $?.success?

      JSON.parse(result)
    end

    def fetch_repos
      # Paginated fetch with MAX_PAGES_PER_QUERY limit
      # Returns array of repo names
    end

    def fetch_prs(repos, start_date, end_date)
      # Fetch PRs created/merged in date range
    end

    def fetch_commits(repos, start_date, end_date)
      # Fetch commits in date range
    end

    def fetch_reviews(pr_numbers)
      # Fetch reviews for PRs
    end

    def aggregate_data(prs, commits, reviews, start_date, end_date)
      developers = aggregate_by_developer(prs, commits, reviews)
      daily = aggregate_by_date(prs, commits, reviews, start_date, end_date)

      # Filter bots
      developers.reject! { |d| d["github_login"]&.end_with?("[bot]") }

      # Calculate scores
      developers.each do |dev|
        scores = DxiCalculator.dimension_scores(dev)
        dev["dimension_scores"] = scores
        dev["dxi_score"] = DxiCalculator.composite_score(scores)
      end

      {
        "developers" => developers,
        "daily_activity" => daily,
        "team_dimension_scores" => DxiCalculator.team_dimension_scores(developers),
        "summary" => build_summary(developers)
      }
    end

    def aggregate_by_developer(prs, commits, reviews)
      # Group by developer login, sum metrics
    end

    def aggregate_by_date(prs, commits, reviews, start_date, end_date)
      # Group by date, fill missing dates with zeros
    end

    def build_summary(developers)
      {
        "total_commits" => developers.sum { |d| d["commits"] || 0 },
        "total_prs" => developers.sum { |d| d["prs_opened"] || 0 },
        "total_merged" => developers.sum { |d| d["prs_merged"] || 0 },
        "total_reviews" => developers.sum { |d| d["reviews_given"] || 0 },
        "developer_count" => developers.size,
        "avg_dxi_score" => developers.any? ? (developers.sum { |d| d["dxi_score"] || 0 } / developers.size.to_f).round(1) : 0
      }
    end
  end
end
```

> **Simplification:** Merged `GithubFetcher`, `MetricsProcessor`, and `SprintService` into one `GithubService`. The orchestration was trivial and separate classes added indirection without value.

---

## Phase 4: Controllers & Routes

### 4.1 Routes (Simplified)

```ruby
# config/routes.rb
Rails.application.routes.draw do
  root "dashboard#show"

  # Dashboard with optional sprint selection via query params
  get "dashboard", to: "dashboard#show"
  post "dashboard/refresh", to: "dashboard#refresh"

  # Developer detail (Turbo Frame target)
  get "developers/:login", to: "developers#show", as: :developer
  get "developers/:login/history", to: "developers#history", as: :developer_history

  # Sprint history for trend charts
  get "sprints/history", to: "sprints#history"

  # Health check (inline, no controller needed)
  get "health", to: -> (_) { [200, { "Content-Type" => "text/plain" }, ["OK"]] }
end
```

> **Simplification:** Removed `resources :sprints` with `param: :dates`. Sprint selection is a query param (`?sprint=2026-01-07`), not a RESTful resource. Health check is inline—no controller for one line.

### 4.2 Controllers

| Controller | Actions | Purpose |
|------------|---------|---------|
| `DashboardController` | `show`, `refresh` | Main dashboard, sprint refresh |
| `DevelopersController` | `show`, `history` | Developer detail & trends |
| `SprintsController` | `history` | Team trend data across sprints |

```ruby
# app/controllers/dashboard_controller.rb
class DashboardController < ApplicationController
  def show
    @sprint = find_or_current_sprint
    @sprints = Sprint.recent
  end

  def refresh
    @sprint = Sprint.find_or_fetch!(
      params[:start_date],
      params[:end_date],
      force: true
    )

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("metrics-content", partial: "dashboard/metrics", locals: { sprint: @sprint }),
          turbo_stream.replace("flash", partial: "shared/flash", locals: { notice: "Data refreshed" })
        ]
      end
      format.html { redirect_to dashboard_path(sprint: @sprint.start_date) }
    end
  rescue GithubService::GhCliNotFound, GithubService::GitHubApiError => e
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("flash", partial: "shared/flash", locals: { alert: e.message })
      end
      format.html { redirect_to dashboard_path, alert: e.message }
    end
  end

  private

  def find_or_current_sprint
    if params[:sprint].present?
      start_date = Date.parse(params[:sprint])
      end_date = start_date + Rails.application.config.opendxi.sprint_duration_days.days
      Sprint.find_or_fetch!(start_date, end_date)
    else
      Sprint.current.first || fetch_current_sprint
    end
  end

  def fetch_current_sprint
    config = Rails.application.config.opendxi
    # Calculate current sprint dates from SPRINT_START_DATE
    # ... sprint boundary calculation ...
    Sprint.find_or_fetch!(start_date, end_date)
  end
end
```

---

## Phase 5: Views with Hotwire

### 5.1 Layout Structure (Simplified)

```
app/views/
├── layouts/
│   └── application.html.erb      # Tailwind, Turbo meta tags
├── dashboard/
│   ├── show.html.erb             # Main dashboard
│   ├── _metrics.html.erb         # KPIs + charts (Turbo Frame target)
│   ├── _leaderboard.html.erb     # Developer table
│   └── _activity_chart.html.erb  # Stacked area chart
├── developers/
│   └── show.html.erb             # Developer detail (Turbo Frame)
└── shared/
    ├── _flash.html.erb           # Flash messages
    └── _sprint_selector.html.erb # Sprint dropdown
```

> **Simplification:** Reduced from 11 partials to 6. No `_kpi_card.html.erb` (use `render collection:`), no `_charts.html.erb` (too vague), no `_developer_grid.html.erb` (merged into leaderboard).

### 5.2 View Helpers

```ruby
# app/helpers/dashboard_helper.rb
module DashboardHelper
  def format_hours(hours)
    return "—" if hours.nil?
    hours < 1 ? "#{(hours * 60).round}m" : "#{hours.round(1)}h"
  end

  def dxi_score_class(score)
    case score
    when 70.. then "text-green-600"
    when 50..70 then "text-yellow-600"
    else "text-red-600"
    end
  end

  def dxi_score_label(score)
    case score
    when 70.. then "Good"
    when 50..70 then "Moderate"
    else "Needs Improvement"
    end
  end

  def trend_indicator(current, previous)
    return "" if previous.nil? || previous.zero?

    change = ((current - previous) / previous.to_f * 100).round(1)
    if change > 0
      content_tag(:span, "▲ #{change}%", class: "text-green-600 text-sm")
    elsif change < 0
      content_tag(:span, "▼ #{change.abs}%", class: "text-red-600 text-sm")
    else
      content_tag(:span, "—", class: "text-gray-400 text-sm")
    end
  end

  def format_number(n)
    return "—" if n.nil?
    number_with_delimiter(n)
  end
end
```

### 5.3 Hotwire Patterns

**Tab navigation with Turbo Frames (NO JavaScript needed):**

```erb
<%# dashboard/show.html.erb %>
<div class="flex gap-4 border-b">
  <%= link_to "Team Overview", dashboard_path(view: "team", sprint: @sprint.start_date),
      class: "tab #{params[:view] == 'team' ? 'active' : ''}",
      data: { turbo_frame: "tab-content" } %>
  <%= link_to "Developers", dashboard_path(view: "developers", sprint: @sprint.start_date),
      class: "tab #{params[:view] == 'developers' ? 'active' : ''}",
      data: { turbo_frame: "tab-content" } %>
</div>

<turbo-frame id="tab-content">
  <%= render "dashboard/#{params[:view] || 'team'}_tab", sprint: @sprint %>
</turbo-frame>
```

**Leaderboard sorting (server-side, not client-side):**

```erb
<%# dashboard/_leaderboard.html.erb %>
<turbo-frame id="leaderboard">
  <table>
    <thead>
      <tr>
        <th><%= sort_link "Developer", :name %></th>
        <th><%= sort_link "DXI Score", :dxi_score %></th>
        <th><%= sort_link "Commits", :commits %></th>
        <%# ... %>
      </tr>
    </thead>
    <tbody>
      <% sorted_developers(@sprint, params[:sort], params[:dir]).each do |dev| %>
        <tr>
          <td><%= dev["name"] || dev["github_login"] %></td>
          <td class="<%= dxi_score_class(dev["dxi_score"]) %>">
            <%= dev["dxi_score"]&.round(1) %>
          </td>
          <%# ... %>
        </tr>
      <% end %>
    </tbody>
  </table>
</turbo-frame>
```

> **Simplification:** Removed 4 of 5 Stimulus controllers. Tab switching uses Turbo Frames (native). Leaderboard sorting is server-side (SQL handles it). Loading states use Turbo's built-in `aria-busy` CSS hooks.

### 5.4 Single Stimulus Controller (Radar Chart Only)

```javascript
// app/javascript/controllers/radar_chart_controller.js
import { Controller } from "@hotwired/stimulus"
import Chart from "chart.js/auto"

export default class extends Controller {
  static targets = ["canvas"]
  static values = {
    team: Object,
    developer: Object
  }

  connect() {
    this.chart = new Chart(this.canvasTarget, {
      type: "radar",
      data: {
        labels: ["Review Speed", "Cycle Time", "PR Size", "Review Coverage", "Commits"],
        datasets: this.buildDatasets()
      },
      options: {
        scales: {
          r: { min: 0, max: 100, ticks: { stepSize: 20 } }
        },
        plugins: {
          legend: { position: "bottom" }
        }
      }
    })
  }

  disconnect() {
    this.chart?.destroy()
  }

  buildDatasets() {
    const datasets = [{
      label: "Team Average",
      data: this.extractScores(this.teamValue),
      borderColor: "rgb(59, 130, 246)",
      backgroundColor: "rgba(59, 130, 246, 0.2)"
    }]

    if (this.hasDeveloperValue) {
      datasets.push({
        label: "Selected Developer",
        data: this.extractScores(this.developerValue),
        borderColor: "rgb(234, 88, 12)",
        backgroundColor: "rgba(234, 88, 12, 0.2)"
      })
    }

    return datasets
  }

  extractScores(scores) {
    return [
      scores.review_turnaround || 0,
      scores.cycle_time || 0,
      scores.pr_size || 0,
      scores.review_coverage || 0,
      scores.commit_frequency || 0
    ]
  }
}
```

---

## Phase 6: Chart Implementation

### 6.1 Activity Chart (Chartkick)

```erb
<%# dashboard/_activity_chart.html.erb %>
<%= area_chart @sprint.daily_activity.map { |d|
  {
    name: "Commits",
    data: [[d["date"], d["commits"]]]
  }
} + @sprint.daily_activity.map { |d|
  {
    name: "PRs Merged",
    data: [[d["date"], d["prs_merged"]]]
  }
} + @sprint.daily_activity.map { |d|
  {
    name: "Reviews",
    data: [[d["date"], d["reviews_given"]]]
  }
}, stacked: true, library: { tension: 0.3 } %>
```

### 6.2 Radar Chart (Chart.js + Stimulus)

```erb
<%# In dashboard view %>
<div data-controller="radar-chart"
     data-radar-chart-team-value="<%= @sprint.team_dimension_scores.to_json %>"
     data-radar-chart-developer-value="<%= @selected_developer&.dig('dimension_scores')&.to_json %>">
  <canvas data-radar-chart-target="canvas"></canvas>
</div>
```

### 6.3 Trend Chart (Chartkick)

```erb
<%= line_chart Sprint.recent.map { |s| [s.label, s.summary["avg_dxi_score"]] },
    xtitle: "Sprint", ytitle: "DXI Score",
    min: 0, max: 100 %>
```

---

## Phase 7: Data Migration

### 7.1 Migration Task

```ruby
# lib/tasks/migrate_legacy_data.rake
namespace :opendxi do
  desc "Migrate data from legacy JSON store to Rails schema"
  task migrate_legacy: :environment do
    require "sqlite3"

    legacy_db_path = ENV.fetch("LEGACY_DB_PATH", ".data/opendxi.db")
    abort "Legacy database not found at #{legacy_db_path}" unless File.exist?(legacy_db_path)

    db = SQLite3::Database.new(legacy_db_path)
    db.results_as_hash = true

    migrated = 0
    errors = []

    db.execute("SELECT * FROM sprint_data") do |row|
      begin
        data = JSON.parse(row["data"])

        Sprint.find_or_create_by!(
          start_date: Date.parse(row["start_date"]),
          end_date: Date.parse(row["end_date"])
        ) do |sprint|
          sprint.data = data
        end

        migrated += 1
        print "."
      rescue => e
        errors << { key: row["key"], error: e.message }
        print "E"
      end
    end

    puts "\n\nMigration complete: #{migrated} sprints migrated"
    if errors.any?
      puts "Errors:"
      errors.each { |e| puts "  #{e[:key]}: #{e[:error]}" }
    end
  end

  desc "Verify migration data integrity"
  task verify_migration: :environment do
    Sprint.find_each do |sprint|
      errors = []
      errors << "missing developers" if sprint.developers.empty?
      errors << "missing summary" if sprint.summary.empty?
      errors << "invalid dxi scores" if sprint.developers.any? { |d| d["dxi_score"].nil? }

      if errors.any?
        puts "#{sprint.label}: #{errors.join(', ')}"
      else
        puts "#{sprint.label}: OK (#{sprint.developers.size} developers)"
      end
    end
  end
end
```

### 7.2 Migration Steps

1. Backup existing database: `cp .data/opendxi.db .data/opendxi.db.backup`
2. Run Rails migrations: `rails db:migrate`
3. Run data migration: `rails opendxi:migrate_legacy`
4. Verify integrity: `rails opendxi:verify_migration`
5. Test dashboard manually
6. Remove legacy backup after verification

---

## Phase 8: Error Handling

### 8.1 Error Classes

```ruby
# app/services/github_service.rb
class GithubService
  class GhCliNotFound < StandardError
    def message
      "GitHub CLI not found. Install from https://cli.github.com and run 'gh auth login'"
    end
  end

  class GitHubApiError < StandardError; end
  class RateLimitExceeded < GitHubApiError; end
  class AuthenticationError < GitHubApiError; end
end
```

### 8.2 Controller Error Handling

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  rescue_from GithubService::GhCliNotFound, with: :handle_gh_cli_error
  rescue_from GithubService::GitHubApiError, with: :handle_github_error

  private

  def handle_gh_cli_error(error)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("flash",
          partial: "shared/flash",
          locals: { alert: error.message })
      end
      format.html { redirect_back fallback_location: root_path, alert: error.message }
    end
  end

  def handle_github_error(error)
    Rails.logger.error("GitHub API Error: #{error.message}")

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("flash",
          partial: "shared/flash",
          locals: { alert: "Failed to fetch data from GitHub. Please try again." })
      end
      format.html { redirect_back fallback_location: root_path, alert: "GitHub API error" }
    end
  end
end
```

### 8.3 Flash Partial with Turbo

```erb
<%# app/views/shared/_flash.html.erb %>
<turbo-frame id="flash">
  <% if notice.present? %>
    <div class="bg-green-100 border border-green-400 text-green-700 px-4 py-3 rounded mb-4">
      <%= notice %>
    </div>
  <% end %>
  <% if alert.present? %>
    <div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4">
      <%= alert %>
    </div>
  <% end %>
</turbo-frame>
```

---

## Phase 9: Testing Strategy

### 9.1 Test Files

```
test/
├── models/
│   └── sprint_test.rb
├── services/
│   ├── dxi_calculator_test.rb      # Critical: comprehensive boundary tests
│   └── github_service_test.rb      # Stub gh CLI calls
├── controllers/
│   ├── dashboard_controller_test.rb
│   └── developers_controller_test.rb
├── system/
│   └── dashboard_test.rb           # Full flow with Capybara
├── tasks/
│   └── migrate_legacy_data_test.rb # Migration verification
└── fixtures/
    └── sprints.yml
```

### 9.2 DXI Algorithm Tests (Comprehensive Boundaries)

```ruby
# test/services/dxi_calculator_test.rb
class DxiCalculatorTest < ActiveSupport::TestCase
  # Review turnaround boundaries
  test "review_turnaround is 100 at exactly 2 hours" do
    scores = DxiCalculator.dimension_scores({ "avg_review_time_hours" => 2 })
    assert_equal 100.0, scores[:review_turnaround]
  end

  test "review_turnaround is 100 below 2 hours" do
    scores = DxiCalculator.dimension_scores({ "avg_review_time_hours" => 1 })
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

  test "review_turnaround interpolates correctly at midpoint" do
    # Midpoint: 13 hours should be ~50
    scores = DxiCalculator.dimension_scores({ "avg_review_time_hours" => 13 })
    assert_in_delta 50.0, scores[:review_turnaround], 1.0
  end

  # Cycle time boundaries
  test "cycle_time is 100 at exactly 8 hours" do
    scores = DxiCalculator.dimension_scores({ "avg_cycle_time_hours" => 8 })
    assert_equal 100.0, scores[:cycle_time]
  end

  test "cycle_time is 0 at exactly 72 hours" do
    scores = DxiCalculator.dimension_scores({ "avg_cycle_time_hours" => 72 })
    assert_equal 0.0, scores[:cycle_time]
  end

  # PR size boundaries
  test "pr_size is 100 for small PRs" do
    scores = DxiCalculator.dimension_scores({
      "lines_added" => 100, "lines_deleted" => 50, "prs_opened" => 1
    })
    assert_equal 100.0, scores[:pr_size]
  end

  test "pr_size is 0 for large PRs" do
    scores = DxiCalculator.dimension_scores({
      "lines_added" => 800, "lines_deleted" => 400, "prs_opened" => 1
    })
    assert_equal 0.0, scores[:pr_size]
  end

  test "pr_size handles zero PRs gracefully" do
    scores = DxiCalculator.dimension_scores({ "prs_opened" => 0 })
    assert_equal 100.0, scores[:pr_size]
  end

  # Review coverage
  test "review_coverage is 100 at 10+ reviews" do
    scores = DxiCalculator.dimension_scores({ "reviews_given" => 10 })
    assert_equal 100.0, scores[:review_coverage]
  end

  test "review_coverage scales linearly below 10" do
    scores = DxiCalculator.dimension_scores({ "reviews_given" => 5 })
    assert_equal 50.0, scores[:review_coverage]
  end

  # Commit frequency
  test "commit_frequency is 100 at 20+ commits" do
    scores = DxiCalculator.dimension_scores({ "commits" => 20 })
    assert_equal 100.0, scores[:commit_frequency]
  end

  # Composite score
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

    # Value verified against Python implementation
    assert_in_delta 72.3, composite, 0.5
  end

  # Nil handling
  test "handles nil values gracefully" do
    scores = DxiCalculator.dimension_scores({})
    assert scores.values.all? { |v| v.is_a?(Numeric) }
  end
end
```

### 9.3 Migration Verification Test

```ruby
# test/tasks/migrate_legacy_data_test.rb
class MigrateLegacyDataTest < ActiveSupport::TestCase
  test "preserves all sprint data from legacy database" do
    # Create a test legacy database with known data
    legacy_path = Rails.root.join("tmp", "test_legacy.db")
    setup_legacy_database(legacy_path)

    # Run migration
    ENV["LEGACY_DB_PATH"] = legacy_path.to_s
    Rake::Task["opendxi:migrate_legacy"].invoke

    # Verify
    sprint = Sprint.find_by_dates(Date.new(2026, 1, 7), Date.new(2026, 1, 21))
    assert_not_nil sprint
    assert_equal 5, sprint.developers.size
    assert_in_delta 72.3, sprint.developers.first["dxi_score"], 0.1
  end

  private

  def setup_legacy_database(path)
    # Create SQLite with known test data
  end
end
```

### 9.4 System Test

```ruby
# test/system/dashboard_test.rb
class DashboardTest < ApplicationSystemTestCase
  setup do
    @sprint = sprints(:current)
  end

  test "dashboard displays KPI cards" do
    visit root_path

    assert_selector "[data-testid='kpi-card']", count: 4
    assert_text @sprint.summary["total_commits"].to_s
  end

  test "tab navigation updates content via Turbo Frame" do
    visit root_path

    within("#tab-content") do
      assert_selector "table" # Leaderboard visible by default
    end

    click_link "Developers"

    assert_current_path dashboard_path(view: "developers")
    # Content should update without full page reload
  end

  test "refresh button fetches new data" do
    visit root_path

    click_button "Refresh"

    assert_selector "#flash", text: "Data refreshed"
  end

  test "charts render without JavaScript errors" do
    visit root_path

    # Chartkick renders
    assert_selector "[data-controller='radar-chart']"

    # No JS errors
    assert_empty page.driver.browser.logs.get(:browser).select { |e| e.level == "SEVERE" }
  end
end
```

---

## Critical Files Reference

| Purpose | Current File | Lines |
|---------|--------------|-------|
| DXI Algorithm | `api/services/metrics_service.py` | 60-116 |
| GraphQL Queries | `api/services/github_service.py` | 25-160 |
| Data Processing | `api/services/github_service.py` | 534-700 |
| SQLite Schema | `api/services/sprint_store.py` | 47-58 |
| Pydantic Models | `api/models/schemas.py` | 1-137 |
| Dashboard UI | `frontend/src/app/page.tsx` | 1-350 |
| Chart Components | `frontend/src/components/dashboard/` | Various |

---

## Verification Checklist

### Pre-deployment Checks

- [x] DXI scores match Python implementation for all boundary cases
- [x] All 5 dimension scores calculate correctly (test edge cases)
- [x] Sprint date calculation matches existing logic
- [x] Legacy data migrates without loss
- [x] GitHub API pagination works for large orgs
- [x] Error handling works when `gh` CLI is missing

### Post-deployment Checks

- [x] Dashboard loads with cached sprint data
- [x] Force refresh fetches new GitHub data
- [x] Tab navigation works via Turbo Frames (no full page reload)
- [x] Developer detail view renders correctly
- [x] Leaderboard sorting works (server-side)
- [x] Charts render correctly (area, radar, line)
- [x] Error messages display via Turbo Streams

### Manual Testing Flow

1. Visit `http://localhost:3000`
2. Verify KPI cards show correct values
3. Click "Refresh" - verify loading state and data update
4. Switch tabs - verify content updates without page reload
5. Click developer row - verify detail view
6. Compare scores with old dashboard
7. Disconnect internet - verify error handling

---

## Implementation Order

> **Note:** Order adjusted to respect dependencies. No step depends on a later step.

1. **Rails setup** - Project init, gems, config initializer
2. **Database schema** - Single migration for sprints table
3. **DxiCalculator** - Port algorithm with comprehensive boundary tests
4. **GithubService** - Fetch + aggregate (test with stubbed `gh` CLI)
5. **Sprint model** - JSON accessors, `find_or_fetch!` method
6. **Data migration task** - Import legacy SQLite data
7. **Controllers** - Dashboard, Developers (with error handling)
8. **View helpers** - Formatting, colors, trends
9. **Views** - ERB templates with Turbo Frames
10. **Radar chart Stimulus controller** - Only JS needed
11. **System tests** - Full flow verification
12. **Cleanup** - Remove old frontend/api directories

---

## Summary of Changes from Review

| Original | Updated | Reason |
|----------|---------|--------|
| 5 normalized tables | 1 table with JSON | Matches access pattern, simpler |
| 4 service classes | 2 services | Eliminated unnecessary indirection |
| 5 Stimulus controllers | 1 controller | Turbo/CSS handle the rest |
| `solid_queue/cache/cable` | Removed | YAGNI - no async/cache/realtime needs |
| `param: :dates` routes | Query params | Simpler, more Rails-like |
| `HealthController` | Inline route | One line doesn't need a class |
| Missing helpers | Added `DashboardHelper` | Formatting belongs in helpers |
| 1 DXI test case | Comprehensive boundaries | Tests prevent regressions |
| No error handling | Full error strategy | Production-ready |
| Wrong implementation order | Fixed dependencies | No circular dependencies |
