# Validate FRONTEND_URL Environment Variable

**Status:** wontfix
**Priority:** P2 - Important
**Tags:** security, configuration, code-review
**Source:** Security Sentinel

## Problem Statement

The `frontend_url` method reads directly from the `FRONTEND_URL` environment variable without validation. If an attacker gains access to modify environment variables, they could redirect users to a malicious site after OAuth authentication.

## Findings

**File:** `api/app/controllers/sessions_controller.rb:54-59`

```ruby
def frontend_url
  ENV.fetch("FRONTEND_URL", "http://localhost:3001")  # No validation
end

def failure_url(error)
  "#{frontend_url}/login?error=#{error}"  # Error param not URL-encoded
end
```

Additionally, the `error` parameter is not URL-encoded, which could allow injection in edge cases.

## Impact

- **Open Redirect Risk:** Compromised env vars could redirect to phishing sites
- **URL Injection:** Unencoded error param could cause issues

## Proposed Solutions

### Option A: Validate Against Allowlist (Recommended)
**Effort:** Small (30 minutes)

```ruby
ALLOWED_FRONTEND_HOSTS = %w[
  localhost
  dxi.esoxjem.com
].freeze

def frontend_url
  url = ENV.fetch("FRONTEND_URL", "http://localhost:3001")
  uri = URI.parse(url)

  unless ALLOWED_FRONTEND_HOSTS.include?(uri.host)
    Rails.logger.error "Invalid FRONTEND_URL: #{url}"
    return "http://localhost:3001"
  end

  url
end

def failure_url(error)
  "#{frontend_url}/login?error=#{CGI.escape(error)}"
end
```

### Option B: Validate at Boot Time
**Effort:** Small (15 minutes)

Add validation in an initializer to fail fast if `FRONTEND_URL` is suspicious.

## Acceptance Criteria

- [ ] `FRONTEND_URL` is validated against allowed hosts
- [ ] Invalid URLs fall back to safe default
- [ ] Error parameter is URL-encoded
- [ ] Invalid URLs are logged for monitoring

## Work Log

| Date | Action | Notes |
|------|--------|-------|
| 2026-01-23 | Created | Identified during code review |

## Resources

- PR: feat/github-oauth-auth branch
- File: `api/app/controllers/sessions_controller.rb`
