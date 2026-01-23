# Add Frontend Logout Error Handling

**Status:** complete
**Priority:** P2 - Important
**Tags:** frontend, error-handling, code-review
**Source:** Pattern Recognition Specialist, Performance Oracle

## Problem Statement

The logout function doesn't handle network failures gracefully. If the logout API call fails, the user is still redirected to login but their session may not be cleared server-side.

## Findings

**File:** `frontend/src/hooks/useAuth.ts:38-42`

```typescript
const logout = async () => {
  await apiLogout();  // No try-catch - failure not handled
  queryClient.setQueryData(["auth"], { authenticated: false });
  window.location.href = "/login";
};
```

Additionally, there's no protection against rapid multiple clicks on the logout button.

## Impact

- **Error State:** Network failure during logout leaves user in undefined state
- **Session Leak:** Server session may remain active if API call fails
- **UX:** No feedback if logout fails

## Proposed Solution

**Effort:** Small (30 minutes)

```typescript
const logout = async () => {
  try {
    await apiLogout();
  } catch (error) {
    // Log error but still proceed with client-side logout
    console.error("Logout API failed:", error);
  }
  // Always clear client state and redirect
  queryClient.setQueryData(["auth"], { authenticated: false });
  window.location.href = "/login";
};
```

For debouncing, consider disabling the logout button during the operation or using a flag.

## Acceptance Criteria

- [x] Logout handles network errors gracefully
- [x] User is redirected to login even if API call fails
- [x] Console logs errors for debugging
- [ ] Consider: Disable logout button while operation is in progress

## Work Log

| Date | Action | Notes |
|------|--------|-------|
| 2026-01-23 | Created | Identified during code review |
| 2026-01-23 | Completed | Added try-catch to logout function for graceful error handling |

## Resources

- PR: feat/github-oauth-auth branch
- File: `frontend/src/hooks/useAuth.ts`
