# SSL/HTTPS Not Enforced in Production

---
status: pending
priority: p2
issue_id: "008"
tags: [code-review, security, rails]
dependencies: []
---

## Problem Statement

Both `config.assume_ssl` and `config.force_ssl` are commented out in production configuration, allowing unencrypted HTTP connections.

**Why it matters**: Without forced SSL, session cookies and sensitive developer metrics data could be intercepted by network attackers (MITM attacks).

## Findings

### Evidence from security-sentinel agent:

**File**: `api/config/environments/production.rb`
**Lines**: 27-28 (commented out)

```ruby
# config.assume_ssl = true
# config.force_ssl = true
```

## Proposed Solutions

### Option A: Enable force_ssl (Recommended)

```ruby
config.force_ssl = true
config.ssl_options = {
  redirect: { exclude: ->(request) { request.path == "/up" } }
}
```

| Aspect | Assessment |
|--------|------------|
| Pros | Standard Rails security practice |
| Cons | Requires HTTPS certificate in production |
| Effort | Trivial |
| Risk | None (if HTTPS already configured) |

## Recommended Action

_To be filled during triage_

## Technical Details

**Affected Files**:
- `api/config/environments/production.rb`

**Note**: Health check endpoint `/up` should be excluded from SSL redirect for load balancer compatibility.

## Acceptance Criteria

- [ ] HTTP requests redirected to HTTPS in production
- [ ] Secure cookies flag set
- [ ] HSTS header present
- [ ] Health check endpoint accessible via HTTP

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-22 | Identified by security-sentinel agent | SSL disabled |

## Resources

- PR #2: https://github.com/esoxjem/OpenDXI/pull/2
- Rails Security Guide: https://guides.rubyonrails.org/security.html
