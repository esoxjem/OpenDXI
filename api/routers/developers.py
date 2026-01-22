"""
Developer-specific endpoints.

Provides endpoints for individual developer metrics and historical trend analysis.
"""

from datetime import datetime
from urllib.parse import unquote

from fastapi import APIRouter, HTTPException, Query

from api.models.schemas import (
    DeveloperHistoryEntry,
    DeveloperHistoryResponse,
    DimensionScores,
    SprintHistoryEntry,
)
from api.services import github_service, metrics_service

router = APIRouter(prefix="/developers", tags=["developers"])


def ensure_dimension_scores(metrics: dict) -> dict:
    """
    Ensure dimension scores exist in metrics data.

    Handles backward compatibility with cached data that doesn't have
    dimension_scores computed.
    """
    for dev in metrics.get("developers", []):
        if "dimension_scores" not in dev:
            dev["dimension_scores"] = metrics_service.calculate_developer_dimension_scores(dev)

    if "team_dimension_scores" not in metrics:
        metrics["team_dimension_scores"] = metrics_service.calculate_dimension_scores(
            metrics.get("developers", [])
        )

    return metrics


@router.get("/{developer_name}/history", response_model=DeveloperHistoryResponse)
async def get_developer_history(
    developer_name: str,
    count: int = Query(6, ge=1, le=12, description="Number of sprints to include"),
) -> DeveloperHistoryResponse:
    """
    Get historical metrics for a specific developer across multiple sprints.

    Returns the developer's metrics over time along with team averages for
    comparison in trend analysis charts.

    Args:
        developer_name: URL-encoded developer name/username
        count: Number of sprints to include (1-12, default 6)
    """
    # URL decode the developer name to handle spaces and special characters
    decoded_name = unquote(developer_name)

    sprints_data = github_service.get_all_sprints(limit=count)
    developer_entries: list[DeveloperHistoryEntry] = []
    team_entries: list[SprintHistoryEntry] = []

    for sprint in sprints_data:
        start_date = sprint["start"]
        end_date = sprint["end"]

        # Fetch metrics for this sprint (uses cache if available)
        metrics = github_service.get_metrics_for_sprint(start_date, end_date, force_refresh=False)
        metrics = ensure_dimension_scores(metrics)

        developers = metrics.get("developers", [])
        summary = metrics.get("summary", {})
        team_scores = metrics.get("team_dimension_scores", {})

        # Create short sprint label (e.g., "Jan 7-20")
        start_dt = datetime.strptime(start_date, "%Y-%m-%d")
        end_dt = datetime.strptime(end_date, "%Y-%m-%d")
        if start_dt.month == end_dt.month:
            label = f"{start_dt.strftime('%b')} {start_dt.day}-{end_dt.day}"
        else:
            label = f"{start_dt.strftime('%b %d')}-{end_dt.strftime('%b %d')}"

        # Add team entry for comparison
        team_entries.append(
            SprintHistoryEntry(
                sprint_label=label,
                start_date=start_date,
                end_date=end_date,
                avg_dxi_score=summary.get("avg_dxi_score", 0),
                dimension_scores=DimensionScores(**team_scores) if team_scores else DimensionScores(
                    review_speed=0,
                    cycle_time=0,
                    pr_size=0,
                    review_coverage=0,
                    commit_frequency=0,
                ),
                developer_count=len(developers),
                total_commits=summary.get("total_commits", 0),
                total_prs=summary.get("total_prs", 0),
            )
        )

        # Find the specific developer in this sprint
        dev_data = next((d for d in developers if d["developer"] == decoded_name), None)

        if dev_data:
            dim_scores = dev_data.get("dimension_scores", {})
            developer_entries.append(
                DeveloperHistoryEntry(
                    sprint_label=label,
                    start_date=start_date,
                    end_date=end_date,
                    dxi_score=dev_data.get("dxi_score", 0),
                    dimension_scores=DimensionScores(**dim_scores) if dim_scores else DimensionScores(
                        review_speed=0,
                        cycle_time=0,
                        pr_size=0,
                        review_coverage=0,
                        commit_frequency=0,
                    ),
                    commits=dev_data.get("commits", 0),
                    prs_opened=dev_data.get("prs_opened", 0),
                    prs_merged=dev_data.get("prs_merged", 0),
                    reviews_given=dev_data.get("reviews_given", 0),
                    lines_added=dev_data.get("lines_added", 0),
                    lines_deleted=dev_data.get("lines_deleted", 0),
                    avg_review_time_hours=dev_data.get("avg_review_time_hours"),
                    avg_cycle_time_hours=dev_data.get("avg_cycle_time_hours"),
                )
            )

    # Reverse to chronological order (oldest first) for charting
    developer_entries.reverse()
    team_entries.reverse()

    if not developer_entries:
        raise HTTPException(
            status_code=404,
            detail=f"Developer '{decoded_name}' not found in any of the last {count} sprints",
        )

    return DeveloperHistoryResponse(
        developer=decoded_name,
        sprints=developer_entries,
        team_history=team_entries,
    )
