---
title: "TanStack Query v5 Incomplete Generic Types Breaking TypeScript Compilation"
module: "OpenDXI Frontend"
date: 2026-01-23
problem_type: "build_error"
component: "react_hooks"
severity: "critical"
symptoms:
  - "TypeScript compilation error: Property 'summary' does not exist on type '{}'"
  - "Frontend deployment fails with type inference error in useMetrics hook"
  - "Error occurs at line 162 in app/page.tsx when accessing metrics?.summary"
  - "Stale string values invalid for refetchOnMount/refetchOnWindowFocus options"
root_cause: "incomplete_generic_parameters"
tags:
  - "tanstack-query"
  - "typescript-generics"
  - "react-query"
  - "type-inference"
  - "deployment-blocker"
affected_files:
  - "frontend/src/hooks/useMetrics.ts"
  - "frontend/src/app/page.tsx"
related_versions:
  - "@tanstack/react-query: 5.90.18"
  - "typescript: 5.x"
---

## Symptom

Frontend deployment fails with TypeScript compilation error:

```
Type error: Property 'summary' does not exist on type 'NonNullable<NoInfer<TQueryFnData>>'
  Location: frontend/src/app/page.tsx:162:28

Type '"stale"' is not assignable to type 'boolean | "always"'
  Location: frontend/src/hooks/useMetrics.ts:61
```

The `useMetrics` hook returns data typed as `{}`, preventing access to properties like `metrics?.summary`.

## Root Cause

TanStack Query v5's `useQuery` hook requires **four** generic type parameters:

```typescript
useQuery<TQueryFnData, TError, TData, TQueryKey>
```

The buggy code only provided one generic:

```typescript
// ❌ WRONG - Only provides TQueryFnData
return useQuery<MetricsResponse>({
  queryKey: ["metrics", startDate, endDate],
  queryFn: () => fetchMetrics(startDate!, endDate!),
  enabled: !!startDate && !!endDate,
  staleTime: 1000 * 60 * 5,
  gcTime: 1000 * 60 * 30,
  refetchOnMount: 'stale',         // ❌ Invalid string value
  refetchOnWindowFocus: 'stale',   // ❌ Invalid string value
});
```

When only `TQueryFnData` is specified, TypeScript cannot infer the final `TData` type, causing it to default to `{}`. This breaks property access downstream.

Additionally, TanStack Query v5 no longer accepts `'stale'` as a string value for refetch options—only boolean or `'always'` are valid.

## Investigation Details

1. **Initial Error**: Coolify deployment failed with TypeScript compilation error
2. **Code Review**: Feature-dev code-reviewer agent analyzed the type parameters
3. **Discovery**: Incomplete generic type parameters identified as root cause
4. **Secondary Issue**: Invalid refetch behavior values also found

## Solution

Provide all four generic type parameters and use valid refetch values:

```typescript
// ✅ CORRECT - Provides all four generics
return useQuery<MetricsResponse, Error, MetricsResponse>({
  //                ^              ^      ^ TData type
  //                TQueryFnData   TError
  queryKey: ["metrics", startDate, endDate],
  queryFn: () => fetchMetrics(startDate!, endDate!),
  enabled: !!startDate && !!endDate,
  staleTime: 1000 * 60 * 5,
  gcTime: 1000 * 60 * 30,
  refetchOnMount: true,            // ✅ Valid boolean value
  refetchOnWindowFocus: true,      // ✅ Valid boolean value
});
```

**Applied to all hooks:**

- `useMetrics`: `useQuery<MetricsResponse, Error, MetricsResponse>`
- `useSprintHistory`: `useQuery<SprintHistoryEntry[], Error, SprintHistoryEntry[]>`
- `useDeveloperHistory`: `useQuery<DeveloperHistoryResponse, Error, DeveloperHistoryResponse>`

## Code Changes

**File**: `frontend/src/hooks/useMetrics.ts`

```diff
  export function useMetrics(startDate: string | undefined, endDate: string | undefined) {
-   return useQuery<MetricsResponse>({
+   return useQuery<MetricsResponse, Error, MetricsResponse>({
      queryKey: ["metrics", startDate, endDate],
      queryFn: () => fetchMetrics(startDate!, endDate!),
      enabled: !!startDate && !!endDate,
      staleTime: 1000 * 60 * 5,
      gcTime: 1000 * 60 * 30,
-     refetchOnMount: 'stale',
+     refetchOnMount: true,
-     refetchOnWindowFocus: 'stale',
+     refetchOnWindowFocus: true,
    });
  }

  export function useSprintHistory(count = 6) {
-   return useQuery({
+   return useQuery<SprintHistoryEntry[], Error, SprintHistoryEntry[]>({
      queryKey: ["sprintHistory", count],
      queryFn: () => fetchSprintHistory(count),
      staleTime: 1000 * 60 * 60,
    });
  }

  export function useDeveloperHistory(developerName: string | undefined, count = 6) {
-   return useQuery({
+   return useQuery<DeveloperHistoryResponse, Error, DeveloperHistoryResponse>({
      queryKey: ["developerHistory", developerName, count],
      queryFn: () => fetchDeveloperHistory(developerName!, count),
      enabled: !!developerName,
      staleTime: 1000 * 60 * 60,
    });
  }
```

## Why This Works

When `TQueryFnData === TData`, TypeScript's type inference chain is complete:

1. `queryFn` returns `Promise<MetricsResponse>`
2. TanStack Query resolves the promise → `MetricsResponse`
3. With `TData = MetricsResponse`, TypeScript knows the hook's `data` property is `MetricsResponse`
4. Accessing `data.summary` is now type-safe ✅

Boolean `true` for `refetchOnMount` and `refetchOnWindowFocus` tells TanStack Query v5 to automatically detect staleness and refetch when needed.

## Verification

```bash
cd frontend
npm run build  # ✅ Build succeeds without TypeScript errors
```

Deployment to production succeeded after this fix:
- Frontend: ✅ Built and deployed successfully
- API: ✅ Health check passing
- Metrics endpoint: ✅ Returns proper data structure

## Prevention

1. **Always provide complete generic types** when using `useQuery` in TanStack Query v5
2. **Run `npm run build` locally** before committing TypeScript changes
3. **Consult TanStack Query v5 migration guide** if upgrading from earlier versions
4. **Use type-aware IDE** that catches incomplete generics during development
5. **Add pre-commit hook** to run TypeScript check before pushing

## Prevention Checklist

- [ ] All `useQuery` calls have four generic parameters: `<TQueryFnData, TError, TData, TQueryKey>`
- [ ] Refetch options (`refetchOnMount`, `refetchOnWindowFocus`) use boolean or `'always'`, not string `'stale'`
- [ ] Local `npm run build` succeeds with no TypeScript errors
- [ ] Type imports include all referenced types (e.g., `SprintHistoryEntry`)

## References

- [TanStack Query v5 Migration Guide](https://tanstack.com/query/latest/docs/react/guides/important-defaults)
- [TanStack Query v5 useQuery API](https://tanstack.com/query/latest/docs/react/reference/useQuery)
- [TypeScript Generics Best Practices](https://www.typescriptlang.org/docs/handbook/2/generics.html)

## Related Issues

- See: `coolify-docker-deployment-fixes.md` (related deployment context)

## Commit Reference

- Commit: `b94a2a9` - "fix(frontend): Fix TanStack Query v5 generic types in hooks"
- PR: Part of ongoing performance optimization
