# frozen_string_literal: true

# GitHub GraphQL API Service
#
# Fetches repository metrics using the `gh` CLI tool. This approach leverages
# local GitHub authentication and avoids managing tokens directly.
#
# Note: Uses synchronous subprocess calls. For production at scale,
# consider migrating to Faraday with GITHUB_TOKEN.
class GithubService
  class GhCliNotFound < StandardError
    def message
      "GitHub CLI not found. Install from https://cli.github.com and run 'gh auth login'"
    end
  end

  class GitHubApiError < StandardError; end
  class RateLimitExceeded < GitHubApiError; end
  class AuthenticationError < GitHubApiError; end

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
          }
        }
      }
    }
  GRAPHQL

  REVIEWS_QUERY = <<~GRAPHQL
    query($owner: String!, $repo: String!, $prNumber: Int!, $cursor: String) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $prNumber) {
          reviews(first: 100, after: $cursor) {
            pageInfo { hasNextPage endCursor }
            nodes {
              author { login }
              submittedAt
              state
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
      validate_gh_cli!
      validate_github_org!

      since_date = start_date.to_s
      until_date = end_date.to_s
      since_iso = "#{since_date}T00:00:00Z"
      org = config.github_org

      # Step 1: Get all active repos
      all_repos = fetch_all_pages(REPOS_QUERY, { org: org }, %w[organization repositories])
      return empty_response if all_repos.empty?

      # Step 2: Filter to repos with activity in sprint window
      active_repos = all_repos.select do |r|
        !r["isArchived"] && !r["isFork"] && r["pushedAt"].to_s[0, 10] >= since_date
      end
      return empty_response if active_repos.empty?

      # Step 3: Fetch PRs for each active repo
      all_prs = []
      active_repos.each do |repo|
        prs = fetch_all_pages(PRS_QUERY, { owner: org, repo: repo["name"] }, %w[repository pullRequests])
        prs.each do |pr|
          created_date = pr["createdAt"].to_s[0, 10]
          if created_date >= since_date && created_date <= until_date
            pr["_repo"] = repo["name"]
            all_prs << pr
          end
        end
      end

      # Step 4: Fetch reviews for each PR
      all_prs.each do |pr|
        reviews = fetch_all_pages(
          REVIEWS_QUERY,
          { owner: org, repo: pr["_repo"], prNumber: pr["number"] },
          %w[repository pullRequest reviews]
        )
        pr["reviews"] = { "nodes" => reviews }
      end

      # Step 5: Fetch commits for each active repo
      all_commits = []
      active_repos.each do |repo|
        commits = fetch_all_pages(
          COMMITS_QUERY,
          { owner: org, repo: repo["name"], since: since_iso },
          %w[repository defaultBranchRef target history]
        )
        all_commits.concat(commits)
      end

      # Step 6: Process into dashboard format
      aggregate_data(all_prs, all_commits, since_date, until_date)
    end

    private

    def config
      Rails.application.config.opendxi
    end

    def validate_gh_cli!
      result = `which gh 2>/dev/null`.strip
      raise GhCliNotFound if result.empty?
    end

    def validate_github_org!
      raise GitHubApiError, "GITHUB_ORG environment variable not set" if config.github_org.blank?
    end

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

    def run_graphql(query, variables)
      args = [ "api", "graphql", "-f", "query=#{query}" ]
      variables.each do |key, value|
        next if value.nil?
        args += [ "-F", "#{key}=#{value}" ]
      end

      stdout, stderr, status = Open3.capture3("gh", *args)

      unless status.success?
        if stderr.include?("rate limit")
          raise RateLimitExceeded, "GitHub API rate limit exceeded"
        elsif stderr.include?("authentication") || stderr.include?("401")
          raise AuthenticationError, "GitHub authentication failed. Run 'gh auth login'"
        else
          raise GitHubApiError, "GitHub API error: #{stderr}"
        end
      end

      JSON.parse(stdout)
    rescue JSON::ParserError => e
      raise GitHubApiError, "Invalid JSON response: #{e.message}"
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

    def aggregate_data(prs, commits, since_date, until_date)
      developer_stats = Hash.new do |h, k|
        h[k] = {
          "commits" => 0, "prs_opened" => 0, "prs_merged" => 0,
          "reviews_given" => 0, "lines_added" => 0, "lines_deleted" => 0,
          "review_times" => [], "cycle_times" => []
        }
      end

      daily_stats = Hash.new do |h, k|
        h[k] = { "commits" => 0, "prs_opened" => 0, "prs_merged" => 0, "reviews_given" => 0 }
      end

      # Process commits
      commits.each do |commit|
        author = commit.dig("author") || {}
        login = author.dig("user", "login") || author["name"].to_s
        next if login.blank? || login.end_with?("[bot]")

        commit_date = author["date"].to_s[0, 10]
        next if commit_date < since_date || commit_date > until_date

        developer_stats[login]["commits"] += 1
        developer_stats[login]["lines_added"] += commit["additions"].to_i
        developer_stats[login]["lines_deleted"] += commit["deletions"].to_i
        daily_stats[commit_date]["commits"] += 1
      end

      # Process PRs
      prs.each do |pr|
        created_at = pr["createdAt"].to_s
        created_date = created_at[0, 10]
        next if created_date < since_date || created_date > until_date

        author = pr.dig("author", "login").to_s
        next if author.blank? || author.end_with?("[bot]")

        developer_stats[author]["prs_opened"] += 1
        developer_stats[author]["lines_added"] += pr["additions"].to_i
        developer_stats[author]["lines_deleted"] += pr["deletions"].to_i
        daily_stats[created_date]["prs_opened"] += 1

        # Handle merged PRs
        merged_at = pr["mergedAt"]
        if merged_at.present?
          merged_date = merged_at[0, 10]
          if merged_date <= until_date
            developer_stats[author]["prs_merged"] += 1
            daily_stats[merged_date]["prs_merged"] += 1

            # Calculate cycle time
            created_time = Time.parse(created_at)
            merged_time = Time.parse(merged_at)
            cycle_hours = (merged_time - created_time) / 3600.0
            developer_stats[author]["cycle_times"] << cycle_hours
          end
        end

        # Process reviews
        reviews = pr.dig("reviews", "nodes") || []
        reviews.each do |review|
          reviewer = review.dig("author", "login").to_s
          next if reviewer.blank? || reviewer.end_with?("[bot]")

          submitted_at = review["submittedAt"]
          next unless submitted_at.present?

          review_date = submitted_at[0, 10]
          next if review_date > until_date

          developer_stats[reviewer]["reviews_given"] += 1
          daily_stats[review_date]["reviews_given"] += 1

          # Calculate review turnaround
          submitted_time = Time.parse(submitted_at)
          pr_created_time = Time.parse(created_at)
          review_hours = (submitted_time - pr_created_time) / 3600.0
          developer_stats[reviewer]["review_times"] << review_hours if review_hours > 0
        end
      end

      # Calculate averages and DXI scores
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

      # Fill missing dates and build daily activity
      daily_activity = build_daily_activity(daily_stats, since_date, until_date)

      # Build summary
      summary = {
        "total_commits" => developers.sum { |d| d["commits"] },
        "total_prs" => developers.sum { |d| d["prs_opened"] },
        "total_merged" => developers.sum { |d| d["prs_merged"] },
        "total_reviews" => developers.sum { |d| d["reviews_given"] },
        "developer_count" => developers.size,
        "avg_dxi_score" => developers.any? ? (developers.sum { |d| d["dxi_score"] } / developers.size.to_f).round(1) : 0
      }

      {
        "developers" => developers,
        "daily_activity" => daily_activity,
        "summary" => summary,
        "team_dimension_scores" => DxiCalculator.team_dimension_scores(developers).transform_keys(&:to_s)
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
