"""
GitHub GraphQL API service.

Fetches repository metrics using the `gh` CLI tool. This approach leverages
local GitHub authentication and avoids managing tokens directly.

Note: Uses synchronous subprocess calls wrapped in async functions.
For production at scale, consider migrating to httpx with GITHUB_TOKEN.
"""

import json
import subprocess
import time
from collections import defaultdict
from datetime import datetime, timedelta

from api.core.config import settings
from api.services import sprint_store, metrics_service

# In-memory cache for organization repos (refreshed less frequently)
_repos_cache: dict = {"repos": None, "timestamp": 0}
REPOS_CACHE_TTL = 3600  # 1 hour

# GraphQL query for fetching organization repositories
REPOS_QUERY = """
query($org: String!, $cursor: String) {
  organization(login: $org) {
    repositories(first: 100, after: $cursor, orderBy: {field: PUSHED_AT, direction: DESC}) {
      pageInfo {
        hasNextPage
        endCursor
      }
      nodes {
        name
        isArchived
        isFork
        pushedAt
      }
    }
  }
}
"""

# Legacy query - kept for reference, replaced by paginated queries below
_LEGACY_DASHBOARD_QUERY = """
query($org: String!, $since: GitTimestamp!) {
  organization(login: $org) {
    repositories(first: 10, orderBy: {field: PUSHED_AT, direction: DESC}) {
      nodes {
        name
        pullRequests(first: 20, orderBy: {field: CREATED_AT, direction: DESC}) {
          nodes {
            createdAt
            mergedAt
            state
            author { login }
            additions
            deletions
            reviews(first: 3) {
              nodes {
                author { login }
                submittedAt
              }
            }
          }
        }
        defaultBranchRef {
          target {
            ... on Commit {
              history(first: 30, since: $since) {
                nodes {
                  author {
                    user { login }
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
  }
}
"""

# Paginated query for fetching pull requests per repository
PRS_QUERY = """
query($owner: String!, $repo: String!, $cursor: String) {
  repository(owner: $owner, name: $repo) {
    pullRequests(first: 100, after: $cursor, orderBy: {field: CREATED_AT, direction: DESC}) {
      pageInfo {
        hasNextPage
        endCursor
      }
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
"""

# Paginated query for fetching reviews per pull request
REVIEWS_QUERY = """
query($owner: String!, $repo: String!, $prNumber: Int!, $cursor: String) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $prNumber) {
      reviews(first: 100, after: $cursor) {
        pageInfo {
          hasNextPage
          endCursor
        }
        nodes {
          author { login }
          submittedAt
          state
        }
      }
    }
  }
}
"""

# Paginated query for fetching commits per repository
COMMITS_QUERY = """
query($owner: String!, $repo: String!, $since: GitTimestamp!, $cursor: String) {
  repository(owner: $owner, name: $repo) {
    defaultBranchRef {
      target {
        ... on Commit {
          history(first: 100, after: $cursor, since: $since) {
            pageInfo {
              hasNextPage
              endCursor
            }
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
"""


def run_gh_command(args: list[str], timeout: int = 120) -> str | None:
    """Execute a GitHub CLI command."""
    try:
        result = subprocess.run(
            ["gh"] + args,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        if result.returncode == 0:
            return result.stdout.strip()
        return None
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return None


def fetch_graphql(query: str, variables: dict) -> dict | None:
    """Execute a GraphQL query via gh CLI.

    Variables are passed as individual -F flags per gh CLI specification.
    """
    args = ["api", "graphql", "-f", f"query={query}"]
    for key, value in variables.items():
        # Handle None values (used for initial cursor)
        if value is None:
            continue
        args.extend(["-F", f"{key}={value}"])

    result = run_gh_command(args, timeout=180)

    if result:
        try:
            return json.loads(result)
        except json.JSONDecodeError:
            return None
    return None


def fetch_all_pages(query: str, variables: dict, path: list[str]) -> list[dict]:
    """
    Fetch all pages of a paginated GraphQL query.

    Uses cursor-based pagination to retrieve complete datasets that would
    otherwise be truncated by GitHub's per-request limits.

    Args:
        query: GraphQL query string with $cursor variable
        variables: Query variables (cursor will be added automatically)
        path: List of keys to navigate to the connection object
              e.g., ["repository", "pullRequests"] for PR queries

    Returns:
        List of all nodes across all pages
    """
    all_nodes = []
    cursor = None
    pages_fetched = 0

    while pages_fetched < settings.max_pages_per_query:
        vars_with_cursor = {**variables, "cursor": cursor}
        result = fetch_graphql(query, vars_with_cursor)

        if not result or "data" not in result:
            break

        # Navigate to the connection object using the path
        connection = result["data"]
        for key in path:
            if connection is None:
                break
            connection = connection.get(key, {})

        if not connection:
            break

        nodes = connection.get("nodes", [])
        all_nodes.extend(nodes)

        page_info = connection.get("pageInfo", {})
        if not page_info.get("hasNextPage"):
            break

        cursor = page_info.get("endCursor")
        pages_fetched += 1

    return all_nodes


def get_sprint_dates(sprint_index: int = 0) -> tuple[str, str]:
    """
    Calculate sprint start and end dates.

    Args:
        sprint_index: 0 = current sprint, -1 = previous sprint, etc.

    Returns:
        Tuple of (start_date, end_date) as ISO date strings
    """
    start = datetime.strptime(settings.sprint_start_date, "%Y-%m-%d")
    today = datetime.now()

    days_since_start = (today - start).days
    current_sprint_num = days_since_start // settings.sprint_duration_days
    target_sprint = current_sprint_num + sprint_index

    sprint_start = start + timedelta(days=target_sprint * settings.sprint_duration_days)
    sprint_end = sprint_start + timedelta(days=settings.sprint_duration_days - 1)

    return sprint_start.strftime("%Y-%m-%d"), sprint_end.strftime("%Y-%m-%d")


def get_all_sprints(limit: int = 6) -> list[dict]:
    """Get list of available sprints for dropdown selector."""
    sprints = []
    for i in range(0, -limit, -1):
        start, end = get_sprint_dates(i)
        label = "Current Sprint" if i == 0 else f"Sprint {start} to {end}"
        sprints.append({
            "label": label,
            "value": f"{start}|{end}",
            "start": start,
            "end": end,
            "is_current": i == 0,
        })
    return sprints


def fetch_all_metrics(since_date: str, until_date: str) -> dict:
    """
    Fetch all metrics from GitHub using GraphQL with full pagination.

    This function orchestrates multiple paginated queries to fetch complete
    data for all repositories, PRs, reviews, and commits within the sprint window.

    Args:
        since_date: Sprint start date (inclusive) in YYYY-MM-DD format
        until_date: Sprint end date (inclusive) in YYYY-MM-DD format

    Returns processed metrics ready for dashboard display.
    """
    since_iso = f"{since_date}T00:00:00Z"
    org = settings.github_org

    empty_response = {
        "developers": [],
        "daily": [],
        "summary": {
            "total_commits": 0,
            "total_prs": 0,
            "total_merged": 0,
            "total_reviews": 0,
            "avg_dxi_score": 0,
        },
    }

    # Step 1: Get all active repos (with pagination)
    all_repos = fetch_all_pages(
        REPOS_QUERY, {"org": org}, ["organization", "repositories"]
    )

    if not all_repos:
        return empty_response

    # Step 2: Filter to repos with activity in sprint window
    # Include repos pushed to on or after the sprint start date
    active_repos = [
        r for r in all_repos
        if not r.get("isArchived")
        and not r.get("isFork")
        and r.get("pushedAt", "")[:10] >= since_date
    ]

    if not active_repos:
        return empty_response

    # Step 3: Fetch PRs for each active repo (with pagination)
    all_prs = []
    for repo in active_repos:
        repo_name = repo["name"]
        prs = fetch_all_pages(
            PRS_QUERY,
            {"owner": org, "repo": repo_name},
            ["repository", "pullRequests"],
        )

        # Filter to PRs created within sprint window
        for pr in prs:
            created_date = pr.get("createdAt", "")[:10]
            if created_date >= since_date:
                pr["_repo"] = repo_name  # Tag with repo for later processing
                all_prs.append(pr)

    # Step 4: Fetch reviews for each PR (with pagination)
    for pr in all_prs:
        reviews = fetch_all_pages(
            REVIEWS_QUERY,
            {"owner": org, "repo": pr["_repo"], "prNumber": pr["number"]},
            ["repository", "pullRequest", "reviews"],
        )
        pr["reviews"] = {"nodes": reviews}

    # Step 5: Fetch commits for each active repo (with pagination)
    all_commits = []
    for repo in active_repos:
        repo_name = repo["name"]
        commits = fetch_all_pages(
            COMMITS_QUERY,
            {"owner": org, "repo": repo_name, "since": since_iso},
            ["repository", "defaultBranchRef", "target", "history"],
        )
        all_commits.extend(commits)

    # Step 6: Process into dashboard format
    return process_paginated_data(all_prs, all_commits, since_date, until_date)


def process_graphql_response(data: dict, since_date: str) -> dict:
    """Process GraphQL response into dashboard-ready format."""
    developer_stats = defaultdict(
        lambda: {
            "commits": 0,
            "prs_opened": 0,
            "prs_merged": 0,
            "reviews_given": 0,
            "lines_added": 0,
            "lines_deleted": 0,
            "review_times": [],
            "cycle_times": [],
        }
    )

    daily_stats = defaultdict(
        lambda: {
            "commits": 0,
            "prs_opened": 0,
            "prs_merged": 0,
            "reviews_given": 0,
        }
    )

    org_data = data.get("data", {}).get("organization", {})
    repositories = org_data.get("repositories", {}).get("nodes", [])

    for repo in repositories:
        # Process commits
        default_branch = repo.get("defaultBranchRef") or {}
        target = default_branch.get("target") or {}
        history = target.get("history", {}).get("nodes", [])

        for commit in history:
            author_data = commit.get("author", {})
            user = author_data.get("user") or {}
            login = user.get("login") or author_data.get("name", "")

            # Filter out bots
            if not login or login.endswith("[bot]"):
                continue

            commit_date = author_data.get("date", "")[:10]
            if commit_date < since_date:
                continue

            developer_stats[login]["commits"] += 1
            developer_stats[login]["lines_added"] += commit.get("additions", 0)
            developer_stats[login]["lines_deleted"] += commit.get("deletions", 0)
            daily_stats[commit_date]["commits"] += 1

        # Process PRs
        prs = repo.get("pullRequests", {}).get("nodes", [])
        for pr in prs:
            created_at = pr.get("createdAt", "")
            created_date = created_at[:10] if created_at else ""

            if created_date < since_date:
                continue

            author = pr.get("author") or {}
            login = author.get("login", "")

            if not login or login.endswith("[bot]"):
                continue

            developer_stats[login]["prs_opened"] += 1
            developer_stats[login]["lines_added"] += pr.get("additions", 0)
            developer_stats[login]["lines_deleted"] += pr.get("deletions", 0)
            daily_stats[created_date]["prs_opened"] += 1

            # Check if merged
            merged_at = pr.get("mergedAt")
            if merged_at:
                developer_stats[login]["prs_merged"] += 1
                merged_date = merged_at[:10]
                daily_stats[merged_date]["prs_merged"] += 1

                # Calculate cycle time
                created_dt = datetime.fromisoformat(created_at.replace("Z", "+00:00"))
                merged_dt = datetime.fromisoformat(merged_at.replace("Z", "+00:00"))
                cycle_hours = (merged_dt - created_dt).total_seconds() / 3600
                developer_stats[login]["cycle_times"].append(cycle_hours)

            # Process reviews
            reviews = pr.get("reviews", {}).get("nodes", [])
            for review in reviews:
                reviewer = review.get("author") or {}
                reviewer_login = reviewer.get("login", "")

                if not reviewer_login or reviewer_login.endswith("[bot]"):
                    continue

                developer_stats[reviewer_login]["reviews_given"] += 1

                submitted_at = review.get("submittedAt")
                if submitted_at:
                    review_date = submitted_at[:10]
                    daily_stats[review_date]["reviews_given"] += 1

                    # Calculate review turnaround time
                    submitted_dt = datetime.fromisoformat(submitted_at.replace("Z", "+00:00"))
                    pr_created_dt = datetime.fromisoformat(created_at.replace("Z", "+00:00"))
                    review_hours = (submitted_dt - pr_created_dt).total_seconds() / 3600
                    if review_hours > 0:
                        developer_stats[reviewer_login]["review_times"].append(review_hours)

    # Calculate averages and DXI scores
    developers = []
    for login, stats in developer_stats.items():
        avg_review_time = (
            sum(stats["review_times"]) / len(stats["review_times"]) if stats["review_times"] else None
        )
        avg_cycle_time = (
            sum(stats["cycle_times"]) / len(stats["cycle_times"]) if stats["cycle_times"] else None
        )

        dev_metrics = {
            "developer": login,
            "commits": stats["commits"],
            "prs_opened": stats["prs_opened"],
            "prs_merged": stats["prs_merged"],
            "reviews_given": stats["reviews_given"],
            "lines_added": stats["lines_added"],
            "lines_deleted": stats["lines_deleted"],
            "avg_review_time_hours": avg_review_time,
            "avg_cycle_time_hours": avg_cycle_time,
        }
        dev_metrics["dxi_score"] = metrics_service.calculate_dxi_score(dev_metrics)
        developers.append(dev_metrics)

    # Sort by DXI score
    developers.sort(key=lambda x: x.get("dxi_score") or 0, reverse=True)

    # Convert daily stats to sorted list
    daily_list = [{"date": date, **stats} for date, stats in sorted(daily_stats.items())]

    return {
        "developers": developers,
        "daily": daily_list,
        "summary": {
            "total_commits": sum(d["commits"] for d in developers),
            "total_prs": sum(d["prs_opened"] for d in developers),
            "total_merged": sum(d["prs_merged"] for d in developers),
            "total_reviews": sum(d["reviews_given"] for d in developers),
            "avg_dxi_score": sum(d["dxi_score"] for d in developers) / len(developers) if developers else 0,
        },
    }


def process_paginated_data(prs: list[dict], commits: list[dict], since_date: str, until_date: str) -> dict:
    """
    Process paginated PR and commit data into dashboard-ready format.

    This function handles the flattened data structure from paginated queries,
    unlike process_graphql_response which handles nested repository data.

    Args:
        prs: List of pull request objects (with embedded reviews)
        commits: List of commit objects
        since_date: Sprint start date for filtering (inclusive)
        until_date: Sprint end date for filtering (inclusive)

    Returns:
        Dashboard-ready metrics dictionary
    """
    developer_stats = defaultdict(
        lambda: {
            "commits": 0,
            "prs_opened": 0,
            "prs_merged": 0,
            "reviews_given": 0,
            "lines_added": 0,
            "lines_deleted": 0,
            "review_times": [],
            "cycle_times": [],
        }
    )

    daily_stats = defaultdict(
        lambda: {
            "commits": 0,
            "prs_opened": 0,
            "prs_merged": 0,
            "reviews_given": 0,
        }
    )

    # Process commits
    for commit in commits:
        author_data = commit.get("author", {})
        user = author_data.get("user") or {}
        login = user.get("login") or author_data.get("name", "")

        # Filter out bots and empty logins
        if not login or login.endswith("[bot]"):
            continue

        commit_date = author_data.get("date", "")[:10]
        if commit_date < since_date:
            continue
        if commit_date > until_date:
            continue

        developer_stats[login]["commits"] += 1
        developer_stats[login]["lines_added"] += commit.get("additions", 0)
        developer_stats[login]["lines_deleted"] += commit.get("deletions", 0)
        daily_stats[commit_date]["commits"] += 1

    # Process PRs
    for pr in prs:
        created_at = pr.get("createdAt", "")
        created_date = created_at[:10] if created_at else ""

        if created_date < since_date:
            continue
        if created_date > until_date:
            continue

        author = pr.get("author") or {}
        login = author.get("login", "")

        if not login or login.endswith("[bot]"):
            continue

        developer_stats[login]["prs_opened"] += 1
        developer_stats[login]["lines_added"] += pr.get("additions", 0)
        developer_stats[login]["lines_deleted"] += pr.get("deletions", 0)
        daily_stats[created_date]["prs_opened"] += 1

        # Check if merged within sprint window
        merged_at = pr.get("mergedAt")
        if merged_at:
            merged_date = merged_at[:10]
            # Only count merges that occurred within the sprint boundaries
            if merged_date <= until_date:
                developer_stats[login]["prs_merged"] += 1
                daily_stats[merged_date]["prs_merged"] += 1

                # Calculate cycle time
                created_dt = datetime.fromisoformat(created_at.replace("Z", "+00:00"))
                merged_dt = datetime.fromisoformat(merged_at.replace("Z", "+00:00"))
                cycle_hours = (merged_dt - created_dt).total_seconds() / 3600
                developer_stats[login]["cycle_times"].append(cycle_hours)

        # Process reviews (embedded in PR from paginated fetch)
        reviews = pr.get("reviews", {}).get("nodes", [])
        for review in reviews:
            reviewer = review.get("author") or {}
            reviewer_login = reviewer.get("login", "")

            if not reviewer_login or reviewer_login.endswith("[bot]"):
                continue

            submitted_at = review.get("submittedAt")
            if submitted_at:
                review_date = submitted_at[:10]
                # Only count reviews submitted within the sprint boundaries
                if review_date > until_date:
                    continue

                developer_stats[reviewer_login]["reviews_given"] += 1
                daily_stats[review_date]["reviews_given"] += 1

                # Calculate review turnaround time
                submitted_dt = datetime.fromisoformat(submitted_at.replace("Z", "+00:00"))
                pr_created_dt = datetime.fromisoformat(created_at.replace("Z", "+00:00"))
                review_hours = (submitted_dt - pr_created_dt).total_seconds() / 3600
                if review_hours > 0:
                    developer_stats[reviewer_login]["review_times"].append(review_hours)

    # Calculate averages and DXI scores
    developers = []
    for login, stats in developer_stats.items():
        avg_review_time = (
            sum(stats["review_times"]) / len(stats["review_times"]) if stats["review_times"] else None
        )
        avg_cycle_time = (
            sum(stats["cycle_times"]) / len(stats["cycle_times"]) if stats["cycle_times"] else None
        )

        dev_metrics = {
            "developer": login,
            "commits": stats["commits"],
            "prs_opened": stats["prs_opened"],
            "prs_merged": stats["prs_merged"],
            "reviews_given": stats["reviews_given"],
            "lines_added": stats["lines_added"],
            "lines_deleted": stats["lines_deleted"],
            "avg_review_time_hours": avg_review_time,
            "avg_cycle_time_hours": avg_cycle_time,
        }
        dev_metrics["dxi_score"] = metrics_service.calculate_dxi_score(dev_metrics)
        developers.append(dev_metrics)

    # Sort by DXI score
    developers.sort(key=lambda x: x.get("dxi_score") or 0, reverse=True)

    # Convert daily stats to sorted list
    daily_list = [{"date": date, **stats} for date, stats in sorted(daily_stats.items())]

    return {
        "developers": developers,
        "daily": daily_list,
        "summary": {
            "total_commits": sum(d["commits"] for d in developers),
            "total_prs": sum(d["prs_opened"] for d in developers),
            "total_merged": sum(d["prs_merged"] for d in developers),
            "total_reviews": sum(d["reviews_given"] for d in developers),
            "avg_dxi_score": sum(d["dxi_score"] for d in developers) / len(developers) if developers else 0,
        },
    }


def get_metrics_for_sprint(start_date: str, end_date: str, force_refresh: bool = False) -> dict:
    """
    Get metrics for a sprint from the store, fetching from GitHub only when needed.

    The SQLite store is the source of truth. GitHub is only queried when:
    - force_refresh=True is passed
    - No data exists in the store for this sprint
    """
    sprint_key = sprint_store.get_sprint_key(start_date, end_date)

    # Return stored data if available (unless force refresh)
    if not force_refresh:
        stored = sprint_store.get_sprint(sprint_key)
        if stored:
            return stored

    # Fetch fresh data from GitHub
    metrics = fetch_all_metrics(start_date, end_date)

    # Save to store
    sprint_store.save_sprint(sprint_key, metrics)

    return metrics
