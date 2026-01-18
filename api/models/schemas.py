"""
Pydantic models for API request/response schemas.

These models define the contract between the FastAPI backend and React frontend.
"""

from pydantic import BaseModel


class DeveloperMetrics(BaseModel):
    """Individual developer metrics for a sprint."""

    developer: str
    commits: int
    prs_opened: int
    prs_merged: int
    reviews_given: int
    lines_added: int
    lines_deleted: int
    avg_review_time_hours: float | None
    avg_cycle_time_hours: float | None
    dxi_score: float


class DailyActivity(BaseModel):
    """Daily activity aggregates for the timeline chart."""

    date: str
    commits: int
    prs_opened: int
    prs_merged: int
    reviews_given: int


class MetricsSummary(BaseModel):
    """Aggregated summary statistics for a sprint."""

    total_commits: int
    total_prs: int
    total_merged: int
    total_reviews: int
    avg_dxi_score: float


class MetricsResponse(BaseModel):
    """Complete metrics response for a sprint."""

    developers: list[DeveloperMetrics]
    daily: list[DailyActivity]
    summary: MetricsSummary


class Sprint(BaseModel):
    """Sprint metadata for the selector dropdown."""

    label: str
    value: str
    start: str
    end: str
    is_current: bool


class SprintListResponse(BaseModel):
    """List of available sprints."""

    sprints: list[Sprint]


class HealthResponse(BaseModel):
    """Health check response."""

    status: str
    version: str = "1.0.0"


class ConfigResponse(BaseModel):
    """Application configuration exposed to frontend."""

    github_org: str
