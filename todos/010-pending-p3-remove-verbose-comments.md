# Remove Verbose Comments

**Status:** pending
**Priority:** P3 - Nice to Have
**Tags:** code-quality, cleanup, code-review
**Source:** Code Simplicity Reviewer

## Problem Statement

The implementation has ~35 lines of comments that explain obvious code or restate what the code already clearly does. This adds cognitive load when reading the codebase.

## Findings

### Verbose OAuth Flow Comment (8 lines)
**File:** `api/app/controllers/sessions_controller.rb:3-10`

The 8-line comment block describes standard OAuth flow that any developer familiar with OAuth already knows.

### Unnecessary "What Code Doesn't Do" Comment
**File:** `api/app/controllers/sessions_controller.rb:28`

```ruby
# OAuth token NOT stored - security best practice
```

If you don't store something, you don't need to explain that you don't store it.

### Over-Commented OmniAuth Config (5 lines)
**File:** `api/config/initializers/omniauth.rb:20-24`

5 lines explaining why GET requests are allowed - a standard OmniAuth configuration decision.

### Decorative ASCII Headers
**File:** `frontend/src/lib/api.ts:20-22, 67-69, 94-96`

```typescript
// ═══════════════════════════════════════════════════════════════════════════
// Authentication Types & Functions
// ═══════════════════════════════════════════════════════════════════════════
```

The file is only 153 lines - it doesn't need visual sectioning.

### Redundant JSDoc
**File:** `frontend/src/lib/api.ts:37-40, 48-51, 59-64`

Functions like `checkAuthStatus()`, `logout()`, `getLoginUrl()` are self-explanatory.

## Impact

- **Cognitive Load:** More text to read without adding value
- **Maintenance:** Comments can become outdated and misleading
- **LOC:** ~35 lines of unnecessary comments

## Proposed Solution

**Effort:** Trivial (30 minutes)

Remove or reduce verbose comments to essential information only. Trust that code is self-documenting.

## Acceptance Criteria

- [ ] Remove verbose OAuth flow comment block
- [ ] Remove "what code doesn't do" comments
- [ ] Simplify OmniAuth config comments to 1 line max
- [ ] Remove decorative ASCII section headers
- [ ] Remove redundant JSDoc for obvious functions

## Work Log

| Date | Action | Notes |
|------|--------|-------|
| 2026-01-23 | Created | Identified during code review |

## Resources

- PR: feat/github-oauth-auth branch
- Files listed above
