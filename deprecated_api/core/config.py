"""
Application configuration using pydantic-settings.

Settings are loaded from environment variables with sensible defaults.
"""

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Application settings with environment variable support."""

    # GitHub configuration
    github_org: str = ""  # Set via GITHUB_ORG env var
    sprint_start_date: str = "2026-01-07"
    sprint_duration_days: int = 14

    # SQLite store configuration
    db_path: str = ".data/opendxi.db"
    db_timeout: int = 30  # Connection timeout in seconds

    # GraphQL pagination settings
    max_pages_per_query: int = 10  # Safety limit to prevent runaway pagination

    # CORS configuration
    cors_origins: list[str] = ["http://localhost:3000"]

    # Server configuration
    host: str = "0.0.0.0"
    port: int = 8000
    debug: bool = True

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"


# Global settings instance
settings = Settings()
