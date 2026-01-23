# Add gcTime to Auth Query for Better Caching

**Status:** pending
**Priority:** P2 - Important
**Tags:** frontend, performance, code-review
**Source:** Performance Oracle

## Problem Statement

The auth status query has a 5-minute `staleTime` but uses the default `gcTime` (also 5 minutes). This means if a user navigates away and returns after 5 minutes, the auth data is garbage collected and a new auth check is triggered.

## Findings

**File:** `frontend/src/hooks/useAuth.ts:31-36`

```typescript
const { data, isLoading, error } = useQuery({
  queryKey: ["auth"],
  queryFn: checkAuthStatus,
  retry: false,
  staleTime: 5 * 60 * 1000, // 5 minutes - data considered fresh
  // gcTime defaults to 5 minutes - may GC auth data
});
```

## Impact

- **Unnecessary API Calls:** Auth checks triggered more often than needed
- **UX:** Brief loading states when returning to app

## Proposed Solution

**Effort:** Trivial (5 minutes)

```typescript
const { data, isLoading, error } = useQuery({
  queryKey: ["auth"],
  queryFn: checkAuthStatus,
  retry: false,
  staleTime: 5 * 60 * 1000,    // 5 minutes - data considered fresh
  gcTime: 30 * 60 * 1000,      // 30 minutes - keep in cache longer
});
```

## Acceptance Criteria

- [ ] Auth query includes explicit `gcTime` of 30 minutes
- [ ] Returning to app within 30 minutes doesn't trigger new auth check

## Work Log

| Date | Action | Notes |
|------|--------|-------|
| 2026-01-23 | Created | Identified during code review |

## Resources

- PR: feat/github-oauth-auth branch
- File: `frontend/src/hooks/useAuth.ts`
- TanStack Query docs: https://tanstack.com/query/latest/docs/framework/react/guides/caching
