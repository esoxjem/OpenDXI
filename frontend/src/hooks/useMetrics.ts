/**
 * TanStack Query hooks for fetching DXI metrics.
 *
 * These hooks handle caching, deduplication, and background refetching
 * of metrics data from the FastAPI backend.
 */

"use client";

import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import {
  apiRequest,
  fetchConfig,
  fetchDeveloperHistory,
  fetchMetrics,
  fetchSprintHistory,
  fetchSprints,
} from "@/lib/api";
import type { MetricsResponse, SprintListResponse, SprintHistoryResponse, ConfigResponse, DeveloperHistoryResponse, SprintHistoryEntry } from "@/types/metrics";

/**
 * Hook to fetch application configuration.
 * Config is cached indefinitely since it rarely changes.
 */
export function useConfig() {
  return useQuery({
    queryKey: ["config"],
    queryFn: fetchConfig,
    staleTime: Infinity,
  });
}

/**
 * Hook to fetch the list of available sprints.
 * Sprints are cached for 1 hour since they change infrequently.
 */
export function useSprints() {
  return useQuery({
    queryKey: ["sprints"],
    queryFn: fetchSprints,
    staleTime: 1000 * 60 * 60, // 1 hour
  });
}

/**
 * Hook to fetch metrics for a specific sprint.
 *
 * Caching strategy:
 * - Data cached for 1 hour (matches backend's hourly GitHub refresh job)
 * - Changing sprints via selector fetches new data (different cache key)
 * - Changing team filter fetches new data (different cache key)
 * - Use the manual "Refresh" button to force-fetch fresh data from GitHub
 */
export function useMetrics(startDate: string | undefined, endDate: string | undefined, team?: string) {
  return useQuery<MetricsResponse, Error, MetricsResponse>({
    queryKey: ["metrics", startDate, endDate, team ?? null],
    queryFn: () => fetchMetrics(startDate!, endDate!, false, team || undefined),
    enabled: !!startDate && !!endDate,
    staleTime: 1000 * 60 * 60, // 1 hour - matches backend refresh cycle
  });
}

/**
 * Hook to force-refresh metrics, bypassing cache.
 * Returns a mutation that can be triggered on demand.
 */
export function useRefreshMetrics() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ start, end, team }: { start: string; end: string; team?: string }) =>
      fetchMetrics(start, end, true, team || undefined),
    onSuccess: (data, { start, end, team }) => {
      // Update the cache with fresh data
      queryClient.setQueryData(["metrics", start, end, team ?? null], data);
    },
  });
}

/**
 * Hook to fetch historical DXI scores across multiple sprints.
 * Uses 1 hour stale time since historical data changes infrequently.
 */
export function useSprintHistory(count = 6, team?: string) {
  return useQuery<SprintHistoryEntry[], Error, SprintHistoryEntry[]>({
    queryKey: ["sprintHistory", count, team ?? null],
    queryFn: () => fetchSprintHistory(count, team || undefined),
    staleTime: 1000 * 60 * 60, // 1 hour
  });
}

/**
 * Hook to fetch historical metrics for a specific developer.
 * Only enabled when developerName is provided.
 * Uses 1 hour stale time since historical data changes infrequently.
 */
export function useDeveloperHistory(developerName: string | undefined, count = 6) {
  return useQuery<DeveloperHistoryResponse, Error, DeveloperHistoryResponse>({
    queryKey: ["developerHistory", developerName, count],
    queryFn: () => fetchDeveloperHistory(developerName!, count),
    enabled: !!developerName,
    staleTime: 1000 * 60 * 60, // 1 hour
  });
}

interface TeamListItem {
  id: number;
  name: string;
  slug: string;
  developer_count: number;
}

/**
 * Hook to fetch the list of teams for the dashboard filter dropdown.
 * Available to all authenticated users.
 * Teams are cached for 5 minutes since they change less frequently than metrics.
 */
export function useTeams() {
  return useQuery<TeamListItem[]>({
    queryKey: ["teams"],
    queryFn: async () => {
      const data = await apiRequest<{ teams: TeamListItem[] }>("/api/teams");
      return data.teams;
    },
    staleTime: 1000 * 60 * 5, // 5 minutes
  });
}
