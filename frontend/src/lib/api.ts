/**
 * API client for the OpenDXI Dashboard FastAPI backend.
 *
 * All API calls are centralized here for easy configuration and error handling.
 */

import type { ConfigResponse, MetricsResponse, Sprint, SprintListResponse } from "@/types/metrics";

const API_BASE = process.env.NEXT_PUBLIC_API_URL || "http://localhost:8000";

/**
 * Fetch application configuration.
 */
export async function fetchConfig(): Promise<ConfigResponse> {
  const res = await fetch(`${API_BASE}/api/config`);
  if (!res.ok) {
    throw new Error("Failed to fetch config");
  }
  return res.json();
}

/**
 * Fetch the list of available sprints.
 */
export async function fetchSprints(): Promise<Sprint[]> {
  const res = await fetch(`${API_BASE}/api/sprints`);
  if (!res.ok) {
    throw new Error("Failed to fetch sprints");
  }
  const data: SprintListResponse = await res.json();
  return data.sprints;
}

/**
 * Fetch metrics for a specific sprint period.
 *
 * @param startDate - Sprint start date (YYYY-MM-DD)
 * @param endDate - Sprint end date (YYYY-MM-DD)
 * @param forceRefresh - Bypass cache and fetch fresh data
 */
export async function fetchMetrics(
  startDate: string,
  endDate: string,
  forceRefresh = false
): Promise<MetricsResponse> {
  const url = new URL(`${API_BASE}/api/sprints/${startDate}/${endDate}/metrics`);
  if (forceRefresh) {
    url.searchParams.set("force_refresh", "true");
  }

  const res = await fetch(url.toString());
  if (!res.ok) {
    throw new Error("Failed to fetch metrics");
  }
  return res.json();
}
