"""
Pydantic models for API request/response schemas.

These models define the contract between the FastAPI backend and React frontend.
"""

from pydantic import BaseModel


class DimensionScores(BaseModel):
    """Individual dimension scores that make up the DXI composite score."""

    review_speed: float
    cycle_time: float
    pr_size: float
    review_coverage: float
    commit_frequency: float


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
    dimension_scores: DimensionScores


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
    team_dimension_scores: DimensionScores


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


class SprintHistoryEntry(BaseModel):
    """Single sprint entry for historical trend analysis."""

    sprint_label: str
    start_date: str
    end_date: str
    avg_dxi_score: float
    dimension_scores: DimensionScores
    developer_count: int
    total_commits: int
    total_prs: int


class SprintHistoryResponse(BaseModel):
    """Historical DXI scores across multiple sprints for trend analysis."""

    sprints: list[SprintHistoryEntry]
