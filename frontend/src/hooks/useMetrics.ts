/**
 * TanStack Query hooks for fetching DXI metrics.
 *
 * These hooks handle caching, deduplication, and background refetching
 * of metrics data from the FastAPI backend.
 */

"use client";

import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import {
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
 * Implements "stale-while-revalidate" pattern for optimal UX:
 * - Data is considered fresh for 5 minutes
 * - After 5 minutes, data becomes stale but continues showing
 * - Stale data remains in memory for 30 minutes (gcTime)
 * - When component mounts or window gains focus, stale data is revalidated
 * - This enables instant UI rendering with background refetch
 */
export function useMetrics(startDate: string | undefined, endDate: string | undefined) {
  return useQuery<MetricsResponse, Error, MetricsResponse>({
    queryKey: ["metrics", startDate, endDate],
    queryFn: () => fetchMetrics(startDate!, endDate!),
    enabled: !!startDate && !!endDate,
    staleTime: 1000 * 60 * 5,       // 5 minutes - data considered fresh
    gcTime: 1000 * 60 * 30,          // 30 minutes - keep in memory for stale-while-revalidate
    refetchOnMount: true,            // Refetch if data is stale when component mounts
    refetchOnWindowFocus: true,      // Refetch if data is stale when window regains focus
  });
}

/**
 * Hook to force-refresh metrics, bypassing cache.
 * Returns a mutation that can be triggered on demand.
 */
export function useRefreshMetrics() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ start, end }: { start: string; end: string }) =>
      fetchMetrics(start, end, true),
    onSuccess: (data, { start, end }) => {
      // Update the cache with fresh data
      queryClient.setQueryData(["metrics", start, end], data);
    },
  });
}

/**
 * Hook to fetch historical DXI scores across multiple sprints.
 * Uses 1 hour stale time since historical data changes infrequently.
 */
export function useSprintHistory(count = 6) {
  return useQuery<SprintHistoryEntry[], Error, SprintHistoryEntry[]>({
    queryKey: ["sprintHistory", count],
    queryFn: () => fetchSprintHistory(count),
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
