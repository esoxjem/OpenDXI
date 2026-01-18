/**
 * TanStack Query hooks for fetching DXI metrics.
 *
 * These hooks handle caching, deduplication, and background refetching
 * of metrics data from the FastAPI backend.
 */

"use client";

import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { fetchConfig, fetchSprints, fetchMetrics } from "@/lib/api";

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
 * Uses 5 minute stale time to match backend's current sprint cache TTL.
 */
export function useMetrics(startDate: string | undefined, endDate: string | undefined) {
  return useQuery({
    queryKey: ["metrics", startDate, endDate],
    queryFn: () => fetchMetrics(startDate!, endDate!),
    enabled: !!startDate && !!endDate,
    staleTime: 1000 * 60 * 5, // 5 minutes
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
