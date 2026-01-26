---
title: Excessive API calls on dashboard tab switching due to short TanStack Query staleTime
slug: tanstack-query-excessive-refetch-on-tab-switch
category: performance-issues
symptoms:
  - Multiple API calls triggered when switching between dashboard tabs
  - Network requests firing on every tab switch even with cached data
  - Unnecessary backend load from redundant data fetching
  - Slower perceived UI responsiveness during tab navigation
root_cause: TanStack Query's staleTime was set to 5 minutes, much shorter than the backend's 1-hour GitHub data refresh cycle. This caused data to be marked "stale" prematurely, triggering refetches on tab switches when the underlying data hadn't actually changed.
components:
  - frontend/src/hooks/useMetrics.ts
  - TanStack Query cache configuration
  - Dashboard tab navigation
tags:
  - tanstack-query
  - react-query
  - caching
  - stale-time
  - api-optimization
  - frontend-performance
  - dashboard
  - data-fetching
severity: medium
date_solved: 2026-01-26
related_commits:
  - 89e97c7
related_docs:
  - docs/solutions/build-errors/tanstack-query-incomplete-generics-frontend-20260123.md
  - docs/AGENT_API.md
---

# Excessive API Calls on Dashboard Tab Switching

## Problem Statement

The OpenDXI dashboard was making excessive API calls to the backend whenever users switched between tabs (Team Overview, Developers, History). This created unnecessary server load and degraded user experience with redundant network requests.

**Observable Symptoms:**
- Multiple `/api/sprints/{start}/{end}/metrics` requests on each tab switch
- Network activity visible in DevTools on every navigation
- Unnecessary load on Rails backend

## Root Cause Analysis

The root cause was a **mismatch between frontend cache freshness and backend data refresh cycle**:

1. **Short `staleTime` (5 minutes)**: The `useMetrics` hook had `staleTime: 1000 * 60 * 5` (5 minutes), meaning data was marked as "stale" very quickly.

2. **Aggressive refetch options**: The hook was configured with:
   - `refetchOnMount: true` - Refetch whenever a component using the hook mounts
   - `refetchOnWindowFocus: true` - Refetch whenever the browser window regains focus

3. **Tab switching triggers remounts**: When users switch between dashboard tabs, React components unmount and remount, triggering the `refetchOnMount` behavior for stale data.

4. **Inconsistency with other hooks**: Other hooks in the same file (`useSprints`, `useSprintHistory`, `useDeveloperHistory`) all used `staleTime: 1 hour` without the aggressive refetch options, making `useMetrics` the outlier.

5. **Mismatch with backend**: The backend has an hourly GitHub refresh job (PR #35), so data only changes once per hour at most. A 5-minute staleTime was unnecessarily aggressive.

### Why TanStack Query Refetched

TanStack Query only triggers refetches on mount/focus for **stale** data. The sequence was:

```
User loads dashboard
  → useMetrics fetches data
  → Data marked fresh for 5 minutes

[5 minutes pass]
  → Data now "stale"

User switches tab (Team → Developers)
  → Component remounts
  → refetchOnMount: true + stale data
  → REFETCH triggered (unnecessary!)
```

## Solution

**File:** `frontend/src/hooks/useMetrics.ts`

**Before:**
```typescript
export function useMetrics(startDate: string | undefined, endDate: string | undefined) {
  return useQuery<MetricsResponse, Error, MetricsResponse>({
    queryKey: ["metrics", startDate, endDate],
    queryFn: () => fetchMetrics(startDate!, endDate!),
    enabled: !!startDate && !!endDate,
    staleTime: 1000 * 60 * 5,       // 5 minutes
    gcTime: 1000 * 60 * 30,          // 30 minutes
    refetchOnMount: true,
    refetchOnWindowFocus: true,
  });
}
```

**After:**
```typescript
/**
 * Hook to fetch metrics for a specific sprint.
 *
 * Caching strategy:
 * - Data cached for 1 hour (matches backend's hourly GitHub refresh job)
 * - Changing sprints via selector fetches new data (different cache key)
 * - Use the manual "Refresh" button to force-fetch fresh data from GitHub
 */
export function useMetrics(startDate: string | undefined, endDate: string | undefined) {
  return useQuery<MetricsResponse, Error, MetricsResponse>({
    queryKey: ["metrics", startDate, endDate],
    queryFn: () => fetchMetrics(startDate!, endDate!),
    enabled: !!startDate && !!endDate,
    staleTime: 1000 * 60 * 60, // 1 hour - matches backend refresh cycle
  });
}
```

### Key Changes

| Option | Before | After | Reason |
|--------|--------|-------|--------|
| `staleTime` | 5 minutes | 1 hour | Match backend's hourly GitHub refresh cycle |
| `gcTime` | 30 minutes | Removed (default) | Unnecessary when staleTime is longer |
| `refetchOnMount` | `true` | Removed (default) | Data stays fresh, so refetch rarely needed |
| `refetchOnWindowFocus` | `true` | Removed (default) | Same reasoning - fresh data doesn't trigger refetch |

### Why This Works

With `staleTime: 1 hour`:
- Data stays "fresh" for the full hour
- Tab switching doesn't trigger API calls because data isn't stale
- Manual refresh still available via the "Refresh" button (uses `useRefreshMetrics` mutation with `force_refresh=true`)

## Verification

### Browser DevTools Method

1. Open browser DevTools → Network tab
2. Navigate to `http://localhost:3001`
3. Filter by `api` requests
4. Load dashboard - observe initial API calls
5. Switch between tabs multiple times
6. **Expected:** Zero additional `/api/sprints/.../metrics` requests

### Rails Server Logs Method

```bash
# Add marker to logs
echo "=== TAB SWITCH TEST ===" >> api/log/development.log

# Switch tabs in browser

# Check logs - should show nothing after marker
tail -20 api/log/development.log
```

**Expected:** No new requests after the marker during tab switching.

### Sprint Selector Verification

Selecting a different sprint SHOULD trigger an API call (different cache key):

1. Click sprint dropdown
2. Select a different sprint
3. **Expected:** ONE new API call for the new sprint dates

## Prevention Guidelines

### 1. Match `staleTime` to Backend Refresh Cycles

```typescript
// BAD
staleTime: 5 * 60 * 1000,  // 5 minutes, but backend refreshes hourly

// GOOD
staleTime: 60 * 60 * 1000, // 1 hour, matches backend refresh cycle
```

### 2. Keep Caching Consistent Across Similar Hooks

All hooks fetching sprint-related data should use the same cache settings:

```typescript
const SPRINT_CACHE_OPTIONS = {
  staleTime: 1000 * 60 * 60, // 1 hour
};

export function useMetrics(...) {
  return useQuery({ ...SPRINT_CACHE_OPTIONS, ... });
}
export function useSprintHistory(...) {
  return useQuery({ ...SPRINT_CACHE_OPTIONS, ... });
}
```

### 3. Remove Redundant Options

When `staleTime` handles freshness, explicit `refetchOnMount` and `refetchOnWindowFocus` are redundant:

```typescript
// These options only trigger refetch for STALE data
// With staleTime: 1 hour, data stays fresh, so they have no effect
refetchOnMount: true,        // Can be removed
refetchOnWindowFocus: true,  // Can be removed
```

### 4. Code Review Checklist

- [ ] Does `staleTime` match or exceed backend data refresh cycle?
- [ ] Are related hooks using consistent cache settings?
- [ ] Are redundant refetch options removed?
- [ ] Is the cache rationale documented in comments?

## Related Documentation

- [TanStack Query v5 Generic Types Fix](../build-errors/tanstack-query-incomplete-generics-frontend-20260123.md)
- [API Documentation with ETag Caching](../../AGENT_API.md)
- [Three-Phase Caching Strategy](../../CLAUDE.md) (Phase 1: Frontend Caching section)

## References

- [TanStack Query Caching Documentation](https://tanstack.com/query/latest/docs/framework/react/guides/caching)
- Commit: `89e97c7` - fix(frontend): Eliminate excessive API calls on dashboard tab switching
- PR #35: Backend hourly GitHub refresh job
