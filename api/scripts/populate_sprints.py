#!/usr/bin/env python3
"""
Pre-populate sprint store with GitHub metrics data.

Usage:
    python -m api.scripts.populate_sprints [--limit N] [--force] [--workers N]
"""

import argparse
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

from api.services import github_service, sprint_store


def log(msg: str) -> None:
    """Unbuffered output for real-time logging."""
    print(msg, flush=True)


def fetch_sprint(sprint: dict, force: bool) -> dict:
    """Fetch a single sprint's data. Returns result dict for logging."""
    start, end = sprint["start"], sprint["end"]
    sprint_key = sprint_store.get_sprint_key(start, end)

    # Check if already populated (unless --force)
    if not force:
        existing = sprint_store.get_sprint(sprint_key)
        if existing and existing.get("developers"):
            return {"sprint": sprint, "status": "skipped", "elapsed": 0, "dev_count": 0}

    start_time = time.time()
    metrics = github_service.fetch_all_metrics(start, end)
    sprint_store.save_sprint(sprint_key, metrics)
    elapsed = time.time() - start_time

    return {
        "sprint": sprint,
        "status": "fetched",
        "elapsed": elapsed,
        "dev_count": len(metrics.get("developers", [])),
    }


def main():
    parser = argparse.ArgumentParser(description="Populate sprint store with GitHub data")
    parser.add_argument("--limit", type=int, default=6, help="Number of sprints to fetch (default: 6)")
    parser.add_argument("--force", action="store_true", help="Force refresh even if data exists")
    parser.add_argument("--workers", type=int, default=3, help="Number of parallel workers (default: 3)")
    args = parser.parse_args()

    # Initialize database
    sprint_store._init_db()

    # Get available sprints
    sprints = github_service.get_all_sprints(limit=args.limit)

    log(f"Populating {len(sprints)} sprints with {args.workers} workers...")

    # Fetch sprints in parallel
    with ThreadPoolExecutor(max_workers=args.workers) as executor:
        futures = {
            executor.submit(fetch_sprint, sprint, args.force): sprint
            for sprint in sprints
        }

        for future in as_completed(futures):
            result = future.result()
            sprint = result["sprint"]
            start, end = sprint["start"], sprint["end"]

            if result["status"] == "skipped":
                log(f"  {start} to {end}: Already populated, skipped")
            else:
                log(f"  {start} to {end}: Done in {result['elapsed']:.1f}s ({result['dev_count']} developers)")

    # Show summary
    stats = sprint_store.get_store_stats()
    log(f"\nStore stats: {stats['entry_count']} sprints, {stats['total_bytes']:,} bytes")


if __name__ == "__main__":
    main()
