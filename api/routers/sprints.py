"""
Sprint and metrics endpoints.

Provides endpoints for fetching sprint metadata and developer metrics.
"""

from fastapi import APIRouter, Query

from api.models.schemas import MetricsResponse, Sprint, SprintListResponse
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
