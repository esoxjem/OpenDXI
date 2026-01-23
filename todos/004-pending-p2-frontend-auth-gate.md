# Add Frontend Authentication Gate

**Status:** complete
**Priority:** P2 - Important
**Tags:** frontend, ux, authentication, code-review
**Source:** Architecture Strategist

## Problem Statement

The main dashboard page does not check authentication before rendering. It relies entirely on API calls returning 401 to trigger redirects. This creates a poor UX where users may see a loading state, flash of content, then redirect.

## Findings

**File:** `frontend/src/app/page.tsx`

```typescript
function DashboardContent() {
  // Immediately starts fetching data without checking auth
  const { data: config } = useConfig();
  const { data: sprints, isLoading: sprintsLoading } = useSprints();
  // ...
}
```

The component starts fetching data before verifying authentication. If unauthenticated:
1. Multiple API calls fire in parallel
2. All return 401
3. Each triggers redirect logic
4. User may see partial/loading UI before redirect

## Impact

- **UX:** Flash of unauthenticated content before redirect
- **Performance:** Multiple unnecessary API calls that all return 401
- **Race Conditions:** Potential race between auth check and data fetches

## Proposed Solution

**Effort:** Small (30 minutes)

Add an auth gate at the top of protected pages:

```typescript
function DashboardContent() {
  const { isAuthenticated, isLoading: authLoading } = useAuth();

  // Gate: check auth before fetching data
  if (authLoading) return <DashboardSkeleton />;
  if (!isAuthenticated) {
    window.location.href = "/login";
    return null;
  }

  // Now safe to fetch data
  const { data: config } = useConfig();
  const { data: sprints, isLoading: sprintsLoading } = useSprints();
  // ...
}
```

Alternatively, create a reusable `AuthGuard` component or use Next.js middleware.

## Acceptance Criteria

- [x] Dashboard checks auth status before fetching data
- [x] Users see loading skeleton while auth is being checked
- [x] Unauthenticated users redirect cleanly without flash of content
- [x] Only authenticated users trigger data fetching

## Work Log

| Date | Action | Notes |
|------|--------|-------|
| 2026-01-23 | Created | Identified during code review |
| 2026-01-23 | Completed | Added auth gate using useAuth hook before data fetching |

## Resources

- PR: feat/github-oauth-auth branch
- File: `frontend/src/app/page.tsx`
- File: `frontend/src/hooks/useAuth.ts`
