# Session Expiration & Authorization Bypass

**Status:** complete
**Priority:** P1 - Critical
**Tags:** security, authentication, code-review
**Source:** Data Integrity Guardian, Architecture Strategist

## Problem Statement

Sessions persist indefinitely and authorization is only checked at login time. If a user is removed from `GITHUB_ALLOWED_USERS`, their existing session continues to work until they manually log out or clear cookies.

## Findings

### 1. No Session Expiration Enforcement
**File:** `api/app/controllers/api/base_controller.rb:37-39`

```ruby
def current_user
  @current_user ||= session[:user]  # Never validates session age
end
```

The `authenticated_at` timestamp is stored in the session but never checked. Sessions are valid forever.

### 2. Authorization Bypass for Existing Sessions
**File:** `api/app/controllers/sessions_controller.rb:23-26`

```ruby
unless authorized_user?(user_info[:login])
  redirect_to failure_url("not_authorized"), allow_other_host: true
  return
end
```

The `authorized_user?` check only runs at login time. Once authenticated, users are never re-checked against the allowlist.

## Impact

- **Security Risk:** A stolen session cookie remains valid indefinitely
- **Access Control Gap:** Revoking a user's access doesn't take effect until they log out
- **Compliance:** May violate security policies requiring session expiration

## Proposed Solutions

### Option A: Add Session Age Validation (Recommended)
**Pros:** Simple, no database needed, immediate effect
**Cons:** Users re-authenticate periodically
**Effort:** Small (1 hour)

```ruby
# api/app/controllers/api/base_controller.rb
def current_user
  return nil unless session[:user]

  # Check session age (24 hours max)
  authenticated_at = Time.parse(session[:authenticated_at]) rescue nil
  return nil if authenticated_at.nil? || authenticated_at < 24.hours.ago

  @current_user ||= session[:user]
end
```

### Option B: Re-check Authorization on Every Request
**Pros:** Immediate revocation takes effect
**Cons:** Adds overhead to every request
**Effort:** Small (1 hour)

```ruby
# api/app/controllers/api/base_controller.rb
def authenticate!
  return render_unauthorized unless current_user
  return render_unauthorized("access_revoked") unless user_still_authorized?
end

def user_still_authorized?
  allowed_users = Rails.application.config.opendxi.allowed_users
  return true if allowed_users.empty?
  allowed_users.include?(current_user["login"]&.downcase)
end
```

### Option C: Combine Both
**Pros:** Defense in depth
**Cons:** More code
**Effort:** Small (1-2 hours)

## Recommended Action

Implement Option C (both session expiration AND continuous authorization checking) for defense in depth.

## Acceptance Criteria

- [x] Sessions expire after 24 hours of inactivity
- [x] Removing a user from `GITHUB_ALLOWED_USERS` immediately revokes their access
- [x] Tests verify session expiration behavior
- [x] Tests verify authorization revocation behavior

## Work Log

| Date | Action | Notes |
|------|--------|-------|
| 2026-01-23 | Created | Identified during code review |
| 2026-01-23 | Completed | Implemented Option C (session expiration + continuous auth) in base_controller.rb and auth_controller.rb |

## Resources

- PR: feat/github-oauth-auth branch
- File: `api/app/controllers/api/base_controller.rb`
- File: `api/app/controllers/sessions_controller.rb`
