# Add Explicit HttpOnly Cookie Flag

**Status:** pending
**Priority:** P2 - Important
**Tags:** security, configuration, code-review
**Source:** Security Sentinel, Architecture Strategist, Data Integrity Guardian

## Problem Statement

The session cookie configuration does not explicitly set `httponly: true`. While Rails' `CookieStore` sets this by default, being explicit about security-critical settings is better practice, especially when other cookie attributes are being explicitly configured.

## Findings

**File:** `api/config/application.rb:30-37`

```ruby
config.middleware.use ActionDispatch::Session::CookieStore,
  key: "_opendxi_session",
  same_site: Rails.env.production? ? :none : :lax,
  secure: Rails.env.production?
  # httpOnly not explicitly set
```

The plan's acceptance criteria (line 764) required:
> Session cookies use `HttpOnly`, `Secure`, `SameSite=None`

## Impact

- **XSS Risk:** If the default is somehow not applied, session cookies could be accessible to JavaScript
- **Defense in Depth:** Explicit is better than implicit for security settings
- **Documentation:** Makes security posture clear to code reviewers

## Proposed Solution

**Effort:** Trivial (5 minutes)

```ruby
config.middleware.use ActionDispatch::Session::CookieStore,
  key: "_opendxi_session",
  same_site: Rails.env.production? ? :none : :lax,
  secure: Rails.env.production?,
  httponly: true  # Explicit is better than implicit for security
```

## Acceptance Criteria

- [ ] Session cookie configuration includes `httponly: true`
- [ ] Verify cookie is not accessible via JavaScript in browser dev tools

## Work Log

| Date | Action | Notes |
|------|--------|-------|
| 2026-01-23 | Created | Identified during code review |

## Resources

- PR: feat/github-oauth-auth branch
- File: `api/config/application.rb`
