"""
Sprint and metrics endpoints.

Provides endpoints for fetching sprint metadata and developer metrics.
"""

from datetime import datetime

from fastapi import APIRouter, Query

from api.models.schemas import (
    MetricsResponse,
    Sprint,
    SprintHistoryEntry,
    SprintHistoryResponse,
    SprintListResponse,
)
from api.services import github_service, metrics_service

router = APIRouter(prefix="/sprints", tags=["sprints"])


def ensure_dimension_scores(metrics: dict) -> dict:
    """
    Ensure dimension scores exist in metrics data.

    Handles backward compatibility with cached data that doesn't have
    dimension_scores computed. This allows old cache entries to work
    without requiring a force refresh.
    """
    # Ensure each developer has dimension_scores
    for dev in metrics.get("developers", []):
        if "dimension_scores" not in dev:
            dev["dimension_scores"] = metrics_service.calculate_developer_dimension_scores(dev)

    # Ensure team_dimension_scores exists
    if "team_dimension_scores" not in metrics:
        metrics["team_dimension_scores"] = metrics_service.calculate_dimension_scores(
            metrics.get("developers", [])
        )

    return metrics


@router.get("", response_model=SprintListResponse)
async def list_sprints() -> SprintListResponse:
    """Get list of available sprints for the selector dropdown."""
    sprints_data = github_service.get_all_sprints()
    sprints = [Sprint(**s) for s in sprints_data]
    return SprintListResponse(sprints=sprints)


@router.get("/history", response_model=SprintHistoryResponse)
async def get_sprint_history(
    count: int = Query(6, ge=1, le=12, description="Number of sprints to include"),
) -> SprintHistoryResponse:
    """
    Get historical DXI scores across multiple sprints for trend analysis.

    Returns aggregated team metrics for the last N sprints, ordered from
    oldest to newest for chronological charting.

    Args:
        count: Number of sprints to include (1-12, default 6)
    """
    sprints_data = github_service.get_all_sprints(limit=count)
    history_entries = []

    for sprint in sprints_data:
        start_date = sprint["start"]
        end_date = sprint["end"]

        # Fetch metrics for this sprint (uses cache if available)
        metrics = github_service.get_metrics_for_sprint(start_date, end_date, force_refresh=False)
        metrics = ensure_dimension_scores(metrics)

        # Calculate team dimension scores
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

        history_entries.append(
            SprintHistoryEntry(
                sprint_label=label,
                start_date=start_date,
                end_date=end_date,
                avg_dxi_score=summary.get("avg_dxi_score", 0),
                dimension_scores=team_scores,
                developer_count=len(developers),
                total_commits=summary.get("total_commits", 0),
                total_prs=summary.get("total_prs", 0),
            )
        )

    # Reverse to chronological order (oldest first) for charting
    history_entries.reverse()

    return SprintHistoryResponse(sprints=history_entries)


@router.get("/{start_date}/{end_date}/metrics", response_model=MetricsResponse)
async def get_sprint_metrics(
    start_date: str,
    end_date: str,
    force_refresh: bool = Query(False, description="Bypass cache and fetch fresh data"),
) -> MetricsResponse:
    """
    Get metrics for a specific sprint period.

    Args:
        start_date: Sprint start date (YYYY-MM-DD)
        end_date: Sprint end date (YYYY-MM-DD)
        force_refresh: If true, bypass cache and fetch fresh data from GitHub
    """
    metrics = github_service.get_metrics_for_sprint(start_date, end_date, force_refresh)
    metrics = ensure_dimension_scores(metrics)
    return MetricsResponse(**metrics)
