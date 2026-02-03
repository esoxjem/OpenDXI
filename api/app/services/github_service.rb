# frozen_string_literal: true

# GitHub GraphQL API Service
#
# Fetches repository metrics using direct HTTP calls to GitHub's GraphQL API.
# Authenticates via GH_TOKEN environment variable (Personal Access Token).
#
# Required scopes for GH_TOKEN:
#   - repo (access private repository data)
#   - read:org (read organization membership)
class GithubService
  class GitHubApiError < StandardError; end
  class RateLimitExceeded < GitHubApiError; end
  class AuthenticationError < GitHubApiError; end
  class UserNotFoundError < GitHubApiError; end

  GITHUB_GRAPHQL_URL = "https://api.github.com/graphql"
  GITHUB_REST_URL = "https://api.github.com"

  REPOS_QUERY = <<~GRAPHQL
    query($org: String!, $cursor: String) {
      organization(login: $org) {
        repositories(first: 100, after: $cursor, orderBy: {field: PUSHED_AT, direction: DESC}) {
          pageInfo { hasNextPage endCursor }
          nodes { name isArchived isFork pushedAt }
        }
      }
    }
  GRAPHQL

  # PRs query with inline reviews (first 20) to eliminate O(PRs) separate API calls.
  # This is a significant performance optimization - instead of fetching reviews
  # separately for each PR, we get them in the same query.
  # Trade-off: Limited to 20 reviews per PR (acceptable for most use cases).
  PRS_QUERY = <<~GRAPHQL
    query($owner: String!, $repo: String!, $cursor: String) {
      repository(owner: $owner, name: $repo) {
        pullRequests(first: 100, after: $cursor, orderBy: {field: CREATED_AT, direction: DESC}) {
          pageInfo { hasNextPage endCursor }
          nodes {
            number
            createdAt
            mergedAt
            state
            author { login }
            additions
            deletions
            reviews(first: 20) {
              nodes {
                author { login }
                submittedAt
                state
              }
            }
          }
        }
      }
    }
  GRAPHQL

  COMMITS_QUERY = <<~GRAPHQL
    query($owner: String!, $repo: String!, $since: GitTimestamp!, $cursor: String) {
      repository(owner: $owner, name: $repo) {
        defaultBranchRef {
          target {
            ... on Commit {
              history(first: 100, after: $cursor, since: $since) {
                pageInfo { hasNextPage endCursor }
                nodes {
                  author {
                    user { login }
                    name
                    date
                  }
                  additions
                  deletions
                }
              }
            }
          }
        }
      }
    }
  GRAPHQL

  class << self
    def fetch_sprint_data(start_date, end_date)
      validate_github_org!

      since_date = start_date.to_s
      until_date = end_date.to_s
      since_iso = "#{since_date}T00:00:00Z"
      org = config.github_org

      log "Fetching sprint #{since_date} to #{until_date} for org: #{org}"

      # Step 1: Get all active repos
      log "  Step 1: Fetching repositories..."
      all_repos = fetch_all_pages(REPOS_QUERY, { org: org }, %w[organization repositories])
      if all_repos.empty?
        log "  No repositories found"
        return empty_response
      end
      log "  Found #{all_repos.size} total repositories"

      # Step 2: Filter to repos with activity in sprint window
      active_repos = all_repos.select do |r|
        !r["isArchived"] && !r["isFork"] && extract_date(r["pushedAt"]) >= since_date
      end
      if active_repos.empty?
        log "  No active repositories in sprint window"
        return empty_response
      end
      log "  Step 2: #{active_repos.size} repos with activity in sprint window"

      # Step 3: Fetch PRs for each active repo (reviews are now inline in the query)
      log "  Step 3: Fetching PRs from #{active_repos.size} repos..."
      all_prs = []
      active_repos.each_with_index do |repo, i|
        prs = fetch_all_pages(PRS_QUERY, { owner: org, repo: repo["name"] }, %w[repository pullRequests])
        prs_in_window = prs.select do |pr|
          created_date = extract_date(pr["createdAt"])
          created_date >= since_date && created_date <= until_date
        end
        prs_in_window.each { |pr| pr["_repo"] = repo["name"] }
        all_prs.concat(prs_in_window)
        log "    [#{i + 1}/#{active_repos.size}] #{repo['name']}: #{prs_in_window.size} PRs" if prs_in_window.any?
      end
      log "  Found #{all_prs.size} total PRs in sprint window"

      # Step 4: Fetch commits for each active repo
      log "  Step 4: Fetching commits from #{active_repos.size} repos..."
      all_commits = []
      active_repos.each_with_index do |repo, i|
        commits = fetch_all_pages(
          COMMITS_QUERY,
          { owner: org, repo: repo["name"], since: since_iso },
          %w[repository defaultBranchRef target history]
        )
        all_commits.concat(commits)
        log "    [#{i + 1}/#{active_repos.size}] #{repo['name']}: #{commits.size} commits" if commits.any?
      end
      log "  Found #{all_commits.size} total commits"

      # Step 5: Process into dashboard format
      log "  Step 5: Aggregating data..."
      result = aggregate_data(all_prs, all_commits, since_date, until_date)
      log "  Done! #{result['developers']&.size || 0} developers, #{result['daily_activity']&.size || 0} daily entries"
      result
    end

    # Returns an empty data structure for sprints with no activity.
    # Used both internally and by controllers for placeholder sprints.
    def empty_response
      {
        "developers" => [],
        "daily_activity" => [],
        "summary" => {
          "total_commits" => 0,
          "total_prs" => 0,
          "total_merged" => 0,
          "total_reviews" => 0,
          "developer_count" => 0,
          "avg_dxi_score" => 0
        },
        "team_dimension_scores" => DxiCalculator.team_dimension_scores([])
      }
    end

    # Fetches a GitHub user by login (username) via REST API.
    #
    # @param login [String] GitHub username
    # @return [Hash, nil] User data hash or nil if not found
    # @raise [GitHubApiError] on API errors (except 404)
    def fetch_user_by_login(login)
      response = rest_connection.get("users/#{login}")

      case response.status
      when 200
        data = JSON.parse(response.body)
        {
          github_id: data["id"],
          login: data["login"],
          name: data["name"],
          avatar_url: data["avatar_url"]
        }
      when 404
        nil
      when 401
        raise AuthenticationError, "GitHub authentication failed. Check GH_TOKEN."
      when 403
        if response.headers["X-RateLimit-Remaining"] == "0"
          raise RateLimitExceeded, "GitHub API rate limit exceeded"
        else
          raise AuthenticationError, "GitHub API permission denied."
        end
      else
        raise GitHubApiError, "GitHub API error: #{response.status}"
      end
    rescue Faraday::Error => e
      raise GitHubApiError, "Connection failed: #{e.message}"
    end

    private

    def rest_connection
      @rest_connection ||= Faraday.new(url: GITHUB_REST_URL) do |f|
        f.request :authorization, "Bearer", ENV.fetch("GH_TOKEN") {
          raise GitHubApiError, "GH_TOKEN not set"
        }
        f.options.timeout = 30
        f.options.open_timeout = 10
      end
    end

    def config
      Rails.application.config.opendxi
    end

    def log(message)
      Rails.logger.info("[GithubService] #{message}")
      puts "[GithubService] #{message}" if Rails.env.development? || $stdout.tty?
    end

    # Extracts the YYYY-MM-DD date portion from an ISO 8601 timestamp string.
    # Example: "2026-01-22T14:30:00Z" -> "2026-01-22"
    def extract_date(iso_timestamp)
      iso_timestamp.to_s[0, 10]
    end

    def validate_github_org!
      raise GitHubApiError, "GITHUB_ORG environment variable not set" if config.github_org.blank?
    end

    def run_graphql(query, variables)
      token = ENV.fetch("GH_TOKEN") do
        raise GitHubApiError, "GH_TOKEN not set. Create one at https://github.com/settings/tokens"
      end

      response = Faraday.post(GITHUB_GRAPHQL_URL) do |req|
        req.options.timeout = 30        # Read timeout (seconds)
        req.options.open_timeout = 10   # Connection timeout (seconds)
        req.headers["Authorization"] = "Bearer #{token}"
        req.headers["Content-Type"] = "application/json"
        req.body = { query: query, variables: variables }.to_json
      end

      body = JSON.parse(response.body)

      case response.status
      when 200
        if body["errors"] && body["data"].nil?
          raise GitHubApiError, "GraphQL error: #{body['errors'].map { |e| e['message'] }.join('; ')}"
        end
        body
      when 401
        raise AuthenticationError, "GitHub authentication failed. Check GH_TOKEN."
      when 403
        # Distinguish between rate limiting and permission denied by checking rate limit headers.
        # GitHub sets X-RateLimit-Remaining to "0" when rate limited, but includes remaining
        # requests when the 403 is due to insufficient permissions.
        if response.headers["X-RateLimit-Remaining"] == "0"
          raise RateLimitExceeded, "GitHub API rate limit exceeded"
        else
          raise AuthenticationError, "GitHub API permission denied. Ensure GH_TOKEN has 'repo' and 'read:org' scopes."
        end
      when 429
        raise RateLimitExceeded, "GitHub API rate limit exceeded"
      else
        raise GitHubApiError, "GitHub API error (#{response.status})"
      end
    rescue Faraday::Error => e
      raise GitHubApiError, "Connection failed: #{e.message}"
    end

    def fetch_all_pages(query, variables, path)
      all_nodes = []
      cursor = nil
      pages_fetched = 0
      max_pages = config.max_pages_per_query

      while pages_fetched < max_pages
        result = run_graphql(query, variables.merge(cursor: cursor))

        return all_nodes unless result&.dig("data")

        # Navigate to connection using path
        connection = result["data"]
        path.each { |key| connection = connection&.dig(key) }
        break unless connection

        nodes = connection["nodes"] || []
        all_nodes.concat(nodes)

        page_info = connection["pageInfo"] || {}
        break unless page_info["hasNextPage"]

        cursor = page_info["endCursor"]
        pages_fetched += 1
      end

      all_nodes
    end

    # Aggregates raw GitHub data into developer metrics and daily activity.
    # Each step is extracted into a focused private method for testability.
    def aggregate_data(prs, commits, since_date, until_date)
      developer_stats = initialize_developer_stats
      daily_stats = initialize_daily_stats

      process_commits(commits, developer_stats, daily_stats, since_date, until_date)
      process_prs(prs, developer_stats, daily_stats, since_date, until_date)

      developers = build_developers_with_scores(developer_stats)
      daily_activity = build_daily_activity(daily_stats, since_date, until_date)
      summary = build_summary(developers)

      {
        "developers" => developers,
        "daily_activity" => daily_activity,
        "summary" => summary,
        "team_dimension_scores" => DxiCalculator.team_dimension_scores(developers).transform_keys(&:to_s)
      }
    end

    def initialize_developer_stats
      Hash.new do |h, k|
        h[k] = {
          "commits" => 0, "prs_opened" => 0, "prs_merged" => 0,
          "reviews_given" => 0, "lines_added" => 0, "lines_deleted" => 0,
          "review_times" => [], "cycle_times" => []
        }
      end
    end

    def initialize_daily_stats
      Hash.new do |h, k|
        h[k] = { "commits" => 0, "prs_opened" => 0, "prs_merged" => 0, "reviews_given" => 0 }
      end
    end

    def process_commits(commits, developer_stats, daily_stats, since_date, until_date)
      commits.each do |commit|
        author = commit.dig("author") || {}
        login = author.dig("user", "login") || author["name"].to_s
        next if login.blank? || login.end_with?("[bot]")

        commit_date = extract_date(author["date"])
        next if commit_date < since_date || commit_date > until_date

        developer_stats[login]["commits"] += 1
        developer_stats[login]["lines_added"] += commit["additions"].to_i
        developer_stats[login]["lines_deleted"] += commit["deletions"].to_i
        daily_stats[commit_date]["commits"] += 1
      end
    end

    def process_prs(prs, developer_stats, daily_stats, since_date, until_date)
      prs.each do |pr|
        created_at = pr["createdAt"].to_s
        created_date = extract_date(created_at)
        next if created_date < since_date || created_date > until_date

        author = pr.dig("author", "login").to_s
        next if author.blank? || author.end_with?("[bot]")

        developer_stats[author]["prs_opened"] += 1
        developer_stats[author]["lines_added"] += pr["additions"].to_i
        developer_stats[author]["lines_deleted"] += pr["deletions"].to_i
        daily_stats[created_date]["prs_opened"] += 1

        process_merged_pr(pr, developer_stats, daily_stats, created_at, author, until_date)
        process_reviews(pr, developer_stats, daily_stats, created_at, until_date)
      end
    end

    def process_merged_pr(pr, developer_stats, daily_stats, created_at, author, until_date)
      merged_at = pr["mergedAt"]
      return unless merged_at.present?

      merged_date = extract_date(merged_at)
      return if merged_date > until_date

      developer_stats[author]["prs_merged"] += 1
      daily_stats[merged_date]["prs_merged"] += 1

      # Calculate cycle time (PR creation to merge)
      cycle_hours = (Time.parse(merged_at) - Time.parse(created_at)) / 3600.0
      developer_stats[author]["cycle_times"] << cycle_hours
    end

    def process_reviews(pr, developer_stats, daily_stats, pr_created_at, until_date)
      reviews = pr.dig("reviews", "nodes") || []

      reviews.each do |review|
        reviewer = review.dig("author", "login").to_s
        next if reviewer.blank? || reviewer.end_with?("[bot]")

        submitted_at = review["submittedAt"]
        next unless submitted_at.present?

        review_date = extract_date(submitted_at)
        next if review_date > until_date

        developer_stats[reviewer]["reviews_given"] += 1
        daily_stats[review_date]["reviews_given"] += 1

        # Calculate review turnaround (PR creation to first review)
        review_hours = (Time.parse(submitted_at) - Time.parse(pr_created_at)) / 3600.0
        developer_stats[reviewer]["review_times"] << review_hours if review_hours > 0
      end
    end

    def build_developers_with_scores(developer_stats)
      developers = developer_stats.map do |login, stats|
        avg_review = stats["review_times"].any? ? (stats["review_times"].sum / stats["review_times"].size) : nil
        avg_cycle = stats["cycle_times"].any? ? (stats["cycle_times"].sum / stats["cycle_times"].size) : nil

        metrics = {
          "developer" => login,
          "github_login" => login,
          "commits" => stats["commits"],
          "prs_opened" => stats["prs_opened"],
          "prs_merged" => stats["prs_merged"],
          "reviews_given" => stats["reviews_given"],
          "lines_added" => stats["lines_added"],
          "lines_deleted" => stats["lines_deleted"],
          "avg_review_time_hours" => avg_review&.round(2),
          "avg_cycle_time_hours" => avg_cycle&.round(2)
        }

        dimension_scores = DxiCalculator.dimension_scores(metrics)
        metrics["dimension_scores"] = dimension_scores.transform_keys(&:to_s)
        metrics["dxi_score"] = DxiCalculator.composite_score(dimension_scores)
        metrics
      end

      # Sort by DXI score descending
      developers.sort_by! { |d| -(d["dxi_score"] || 0) }
    end

    def build_summary(developers)
      {
        "total_commits" => developers.sum { |d| d["commits"] },
        "total_prs" => developers.sum { |d| d["prs_opened"] },
        "total_merged" => developers.sum { |d| d["prs_merged"] },
        "total_reviews" => developers.sum { |d| d["reviews_given"] },
        "developer_count" => developers.size,
        "avg_dxi_score" => developers.any? ? (developers.sum { |d| d["dxi_score"] } / developers.size.to_f).round(1) : 0
      }
    end

    def build_daily_activity(daily_stats, since_date, until_date)
      start = Date.parse(since_date)
      finish = Date.parse(until_date)

      (start..finish).map do |date|
        date_str = date.to_s
        stats = daily_stats[date_str] || {}
        {
          "date" => date_str,
          "commits" => stats["commits"] || 0,
          "prs_opened" => stats["prs_opened"] || 0,
          "prs_merged" => stats["prs_merged"] || 0,
          "reviews_given" => stats["reviews_given"] || 0
        }
      end
    end
  end
end
