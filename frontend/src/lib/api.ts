/**
 * API client for the OpenDXI Dashboard Rails backend.
 *
 * All API calls are centralized here for easy configuration and error handling.
 * IMPORTANT: credentials: "include" is required for session cookies to work cross-origin.
 */

import type {
  ConfigResponse,
  DeveloperHistoryResponse,
  MetricsResponse,
  Sprint,
  SprintHistoryEntry,
  SprintHistoryResponse,
  SprintListResponse,
} from "@/types/metrics";

const API_BASE = process.env.NEXT_PUBLIC_API_URL || "http://localhost:3000";

export interface AuthUser {
  id: number;
  github_id: number;
  login: string;
  name: string | null;
  avatar_url: string;
  role: "owner" | "developer";
}

export interface AuthStatus {
  authenticated: boolean;
  user?: AuthUser;
  login_url?: string;
}

export async function checkAuthStatus(): Promise<AuthStatus> {
  const response = await fetch(`${API_BASE}/api/auth/me`, {
    credentials: "include",
  });
  return response.json();
}

export async function logout(): Promise<void> {
  await fetch(`${API_BASE}/auth/logout`, {
    method: "DELETE",
    credentials: "include",
  });
}

export function getLoginUrl(): string {
  return `${API_BASE}/auth/github`;
}

export async function apiRequest<T>(endpoint: string): Promise<T> {
  const response = await fetch(`${API_BASE}${endpoint}`, {
    credentials: "include",
  });

  if (!response.ok) {
    if (response.status === 401) {
      // Redirect to login on auth failure (only in browser)
      if (typeof window !== "undefined") {
        window.location.href = "/login";
      }
      throw new Error("Unauthorized");
    }
    throw new Error(`API error: ${response.status}`);
  }

  return response.json();
}

export async function fetchConfig(): Promise<ConfigResponse> {
  return apiRequest<ConfigResponse>("/api/config");
}

export async function fetchSprints(): Promise<Sprint[]> {
  const data = await apiRequest<SprintListResponse>("/api/sprints");
  return data.sprints;
}

/**
 * Fetch metrics for a specific sprint period.
 *
 * @param startDate - Sprint start date (YYYY-MM-DD)
 * @param endDate - Sprint end date (YYYY-MM-DD)
 * @param forceRefresh - Bypass cache and fetch fresh data
 * @param team - Optional team slug to filter by
 */
export async function fetchMetrics(
  startDate: string,
  endDate: string,
  forceRefresh = false,
  team?: string
): Promise<MetricsResponse> {
  const params = new URLSearchParams();
  if (forceRefresh) params.set("force_refresh", "true");
  if (team) params.set("team", team);
  const qs = params.toString();
  const endpoint = `/api/sprints/${startDate}/${endDate}/metrics${qs ? `?${qs}` : ""}`;
  return apiRequest<MetricsResponse>(endpoint);
}

/**
 * Fetch historical DXI scores across multiple sprints.
 *
 * @param count - Number of sprints to include (default 6)
 * @param team - Optional team slug to filter by
 */
export async function fetchSprintHistory(count = 6, team?: string): Promise<SprintHistoryEntry[]> {
  const params = new URLSearchParams({ count: count.toString() });
  if (team) params.set("team", team);
  const data = await apiRequest<SprintHistoryResponse>(`/api/sprints/history?${params.toString()}`);
  return data.sprints;
}

/**
 * Fetch historical metrics for a specific developer across multiple sprints.
 *
 * @param developerName - The developer's name/username
 * @param count - Number of sprints to include (default 6)
 */
export async function fetchDeveloperHistory(
  developerName: string,
  count = 6
): Promise<DeveloperHistoryResponse> {
  const encodedName = encodeURIComponent(developerName);
  return apiRequest<DeveloperHistoryResponse>(`/api/developers/${encodedName}/history?count=${count}`);
}
