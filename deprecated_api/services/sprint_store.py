"""
SQLite-based data store for sprint metrics.

This is the source of truth for dashboard data. Data is fetched from GitHub
once and cached indefinitely. Use force_refresh=true to manually refresh.

Uses SQLite with WAL mode for better concurrent read performance
and atomic writes.
"""

import json
import sqlite3
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Generator

from api.core.config import settings

DATA_DIR = Path(__file__).parent.parent.parent / ".data"
DATA_DIR.mkdir(exist_ok=True)

# Database path from settings, resolved relative to project root
DB_PATH = Path(__file__).parent.parent.parent / settings.db_path


def _init_db() -> None:
    """
    Initialize the SQLite database with schema and WAL mode.

    Called on application startup to ensure the database is ready.
    WAL mode enables concurrent readers during writes.
    """
    DB_PATH.parent.mkdir(exist_ok=True)

    with _get_connection() as conn:
        # Enable WAL mode for better concurrent read performance
        conn.execute("PRAGMA journal_mode=WAL")

        # Migrate table name if old schema exists
        cursor = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='sprint_cache'"
        )
        if cursor.fetchone():
            conn.execute("ALTER TABLE sprint_cache RENAME TO sprints")

        # Create the sprints table if it doesn't exist
        conn.execute("""
            CREATE TABLE IF NOT EXISTS sprints (
                sprint_key TEXT PRIMARY KEY,
                sprint_start TEXT NOT NULL,
                sprint_end TEXT NOT NULL,
                data_json TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            )
        """)
        conn.commit()


@contextmanager
def _get_connection() -> Generator[sqlite3.Connection, None, None]:
    """
    Context manager for database connections.

    Handles connection lifecycle and ensures proper cleanup.
    Uses configured timeout for connection attempts.
    """
    conn = sqlite3.connect(
        str(DB_PATH),
        timeout=settings.db_timeout,
        check_same_thread=False
    )
    conn.row_factory = sqlite3.Row
    try:
        yield conn
    finally:
        conn.close()


def get_sprint_key(sprint_start: str, sprint_end: str) -> str:
    """Generate unique key for a sprint period."""
    return f"sprint_{sprint_start}_{sprint_end}"


def get_sprint(sprint_key: str) -> dict | None:
    """Load sprint data from the store."""
    try:
        with _get_connection() as conn:
            cursor = conn.execute(
                "SELECT data_json FROM sprints WHERE sprint_key = ?",
                (sprint_key,)
            )
            row = cursor.fetchone()

            if row is not None:
                return json.loads(row["data_json"])

            return None
    except (sqlite3.Error, json.JSONDecodeError):
        return None


def save_sprint(sprint_key: str, data: dict) -> None:
    """
    Save sprint data to the store.

    Uses INSERT OR REPLACE for upsert behavior. Extracts sprint
    dates from the key for queryability.
    """
    now = time.time()

    # Parse sprint dates from key (format: sprint_YYYY-MM-DD_YYYY-MM-DD)
    parts = sprint_key.split("_")
    sprint_start = parts[1] if len(parts) >= 2 else ""
    sprint_end = parts[2] if len(parts) >= 3 else ""

    try:
        data_json = json.dumps(data, default=str)

        with _get_connection() as conn:
            conn.execute("""
                INSERT OR REPLACE INTO sprints
                (sprint_key, sprint_start, sprint_end, data_json, created_at, updated_at)
                VALUES (?, ?, ?, ?,
                    COALESCE((SELECT created_at FROM sprints WHERE sprint_key = ?), ?),
                    ?)
            """, (sprint_key, sprint_start, sprint_end, data_json, sprint_key, now, now))
            conn.commit()
    except (sqlite3.Error, TypeError):
        pass


def delete_sprint(sprint_key: str) -> None:
    """Remove a specific sprint from the store."""
    try:
        with _get_connection() as conn:
            conn.execute(
                "DELETE FROM sprints WHERE sprint_key = ?",
                (sprint_key,)
            )
            conn.commit()
    except sqlite3.Error:
        pass


def get_store_stats() -> dict[str, Any]:
    """
    Get store statistics for monitoring.

    Returns information about stored entries, total size,
    and age of entries.
    """
    try:
        with _get_connection() as conn:
            cursor = conn.execute("""
                SELECT
                    COUNT(*) as entry_count,
                    SUM(LENGTH(data_json)) as total_bytes,
                    MIN(updated_at) as oldest_update,
                    MAX(updated_at) as newest_update
                FROM sprints
            """)
            row = cursor.fetchone()

            entries_cursor = conn.execute("""
                SELECT sprint_key, sprint_start, sprint_end,
                       LENGTH(data_json) as size_bytes,
                       updated_at
                FROM sprints
                ORDER BY updated_at DESC
            """)
            entries = [dict(row) for row in entries_cursor.fetchall()]

            return {
                "entry_count": row["entry_count"],
                "total_bytes": row["total_bytes"] or 0,
                "oldest_update": row["oldest_update"],
                "newest_update": row["newest_update"],
                "entries": entries
            }
    except sqlite3.Error:
        return {"error": "Failed to get store stats"}
