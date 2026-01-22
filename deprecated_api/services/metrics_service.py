"""
DXI score calculation service.

Implements the Developer Experience Index scoring algorithm with five weighted dimensions:
- Review Turnaround (25%): Time to first review
- PR Cycle Time (25%): PR open to merge duration
- PR Size (20%): Lines changed per PR
- Review Coverage (15%): Reviews given per sprint
- Commit Frequency (15%): Commits per sprint
"""


def calculate_developer_dimension_scores(metrics: dict) -> dict:
    """
    Calculate individual dimension scores for a developer.

    This breaks down the DXI score into its component dimensions,
    allowing identification of which areas need improvement.

    Args:
        metrics: Dictionary containing developer activity metrics

    Returns:
        Dictionary with score for each DXI dimension (0-100)
    """
    # Extract raw values with sensible defaults
    review_time = metrics.get("avg_review_time_hours") or 24
    cycle_time = metrics.get("avg_cycle_time_hours") or 48
    lines_changed = (metrics.get("lines_added", 0) or 0) + (metrics.get("lines_deleted", 0) or 0)
    prs_opened = metrics.get("prs_opened", 0) or 1
    avg_pr_size = lines_changed / max(prs_opened, 1)
    reviews = metrics.get("reviews_given", 0) or 0
    commits = metrics.get("commits", 0) or 0

    # Normalize to 0-100 scores with thresholds from CLAUDE.md
    # Review turnaround: <2h = 100, >24h = 0
    review_score = max(0, min(100, 100 - (review_time - 2) * (100 / 22)))

    # Cycle time: <8h = 100, >72h = 0
    cycle_score = max(0, min(100, 100 - (cycle_time - 8) * (100 / 64)))

    # PR size: <200 lines = 100, >1000 lines = 0
    size_score = max(0, min(100, 100 - (avg_pr_size - 200) * (100 / 800)))

    # Reviews: 10+ = 100, 0 = 0 (per sprint)
    review_cov_score = min(100, reviews * 10)

    # Commits: 20+ = 100, 0 = 0 (per sprint)
    commit_score = min(100, commits * 5)

    return {
        "review_speed": round(review_score, 1),
        "cycle_time": round(cycle_score, 1),
        "pr_size": round(size_score, 1),
        "review_coverage": round(review_cov_score, 1),
        "commit_frequency": round(commit_score, 1),
    }


def calculate_dxi_score(metrics: dict) -> float:
    """
    Calculate DXI composite score from developer metrics.

    Score is normalized to 0-100 scale where:
    - 70+ is considered good
    - 50-70 is moderate
    - Below 50 needs improvement

    Args:
        metrics: Dictionary containing developer activity metrics

    Returns:
        Float score between 0-100
    """
    weights = {
        "review_turnaround": 0.25,
        "pr_cycle_time": 0.25,
        "pr_size": 0.20,
        "review_coverage": 0.15,
        "commit_frequency": 0.15,
    }

    # Extract raw values with sensible defaults
    review_time = metrics.get("avg_review_time_hours") or 24
    cycle_time = metrics.get("avg_cycle_time_hours") or 48
    lines_changed = (metrics.get("lines_added", 0) or 0) + (metrics.get("lines_deleted", 0) or 0)
    prs_opened = metrics.get("prs_opened", 0) or 1
    avg_pr_size = lines_changed / max(prs_opened, 1)
    reviews = metrics.get("reviews_given", 0) or 0
    commits = metrics.get("commits", 0) or 0

    # Normalize to 0-100 scores with thresholds from CLAUDE.md
    # Review turnaround: <2h = 100, >24h = 0
    review_score = max(0, min(100, 100 - (review_time - 2) * (100 / 22)))

    # Cycle time: <8h = 100, >72h = 0
    cycle_score = max(0, min(100, 100 - (cycle_time - 8) * (100 / 64)))

    # PR size: <200 lines = 100, >1000 lines = 0
    size_score = max(0, min(100, 100 - (avg_pr_size - 200) * (100 / 800)))

    # Reviews: 10+ = 100, 0 = 0 (per sprint)
    review_cov_score = min(100, reviews * 10)

    # Commits: 20+ = 100, 0 = 0 (per sprint)
    commit_score = min(100, commits * 5)

    composite = (
        weights["review_turnaround"] * review_score
        + weights["pr_cycle_time"] * cycle_score
        + weights["pr_size"] * size_score
        + weights["review_coverage"] * review_cov_score
        + weights["commit_frequency"] * commit_score
    )

    return round(composite, 1)


def calculate_dimension_scores(developers: list[dict]) -> dict:
    """
    Calculate team-level dimension scores for the radar chart.

    Args:
        developers: List of developer metrics dictionaries

    Returns:
        Dictionary with score for each DXI dimension
    """
    if not developers:
        return {
            "review_speed": 50,
            "cycle_time": 50,
            "pr_size": 50,
            "review_coverage": 50,
            "commit_frequency": 50,
        }

    def safe_avg(values: list) -> float:
        valid = [v for v in values if v is not None]
        return sum(valid) / len(valid) if valid else 0

    review_times = [d.get("avg_review_time_hours") for d in developers]
    cycle_times = [d.get("avg_cycle_time_hours") for d in developers]
    pr_sizes = [
        (d.get("lines_added", 0) + d.get("lines_deleted", 0)) / max(d.get("prs_opened", 1), 1)
        for d in developers
    ]
    reviews = [d.get("reviews_given", 0) for d in developers]
    commits = [d.get("commits", 0) for d in developers]

    avg_review_time = safe_avg(review_times)
    review_score = max(0, min(100, 100 - (avg_review_time - 2) * (100 / 22))) if avg_review_time else 50

    avg_cycle_time = safe_avg(cycle_times)
    cycle_score = max(0, min(100, 100 - (avg_cycle_time - 8) * (100 / 64))) if avg_cycle_time else 50

    avg_pr_size = safe_avg(pr_sizes)
    size_score = max(0, min(100, 100 - (avg_pr_size - 200) * (100 / 800)))

    avg_reviews = safe_avg(reviews)
    review_cov_score = min(100, avg_reviews * 10)

    avg_commits = safe_avg(commits)
    commit_score = min(100, avg_commits * 5)

    return {
        "review_speed": round(review_score, 1),
        "cycle_time": round(cycle_score, 1),
        "pr_size": round(size_score, 1),
        "review_coverage": round(review_cov_score, 1),
        "commit_frequency": round(commit_score, 1),
    }
