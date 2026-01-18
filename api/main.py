"""
FastAPI application entry point.

This module configures the FastAPI app with CORS, routers, and lifespan events.
"""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from api.core.config import settings
from api.routers import health, sprints
from api.services.sprint_store import _init_db


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan handler for startup/shutdown events."""
    # Startup: Initialize SQLite data store
    _init_db()
    print(f"Starting OpenDXI Dashboard API on {settings.host}:{settings.port}")
    yield
    # Shutdown: Cleanup resources
    print("Shutting down OpenDXI Dashboard API")


app = FastAPI(
    title="OpenDXI Dashboard API",
    description="Developer Experience Index metrics API",
    version="1.0.0",
    lifespan=lifespan,
)

# Configure CORS for React frontend
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Register routers
app.include_router(health.router, prefix="/api")
app.include_router(sprints.router, prefix="/api")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "api.main:app",
        host=settings.host,
        port=settings.port,
        reload=settings.debug,
    )
