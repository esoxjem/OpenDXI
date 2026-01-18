"""
Health check and configuration endpoints.

Provides simple endpoints for load balancers, monitoring systems,
and frontend configuration.
"""

from fastapi import APIRouter

from api.core.config import settings
from api.models.schemas import ConfigResponse, HealthResponse

router = APIRouter(tags=["health"])


@router.get("/health", response_model=HealthResponse)
async def health_check() -> HealthResponse:
    """Return API health status."""
    return HealthResponse(status="ok")


@router.get("/config", response_model=ConfigResponse)
async def get_config() -> ConfigResponse:
    """Return application configuration for frontend."""
    return ConfigResponse(github_org=settings.github_org)
