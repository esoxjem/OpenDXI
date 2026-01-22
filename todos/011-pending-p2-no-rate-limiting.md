# No Rate Limiting on API Endpoints

---
status: pending
priority: p2
issue_id: "011"
tags: [code-review, security, performance, rails]
dependencies: []
---

## Problem Statement

The API endpoints have no rate limiting. While GitHub API rate limits are handled, the Rails API itself can be hammered, and the `force_refresh` parameter can trigger expensive GitHub API fetches.

**Why it matters**: An attacker or misbehaving client could exhaust server resources or trigger excessive GitHub API calls, causing denial of service.

## Findings

### Evidence from security-sentinel and performance-oracle agents:

**File**: `api/config/routes.rb`
**Lines**: 5-16 (all API endpoints unprotected)

**File**: `api/app/controllers/api/sprints_controller.rb`
**Lines**: 21-28

```ruby
def metrics
  force_refresh = params[:force_refresh] == "true"
  sprint = Sprint.find_or_fetch!(start_date, end_date, force: force_refresh)
  # No rate limiting on force_refresh!
end
```

**Attack Scenario**:
```bash
# Exhaust GitHub API quota
for i in {1..100}; do
  curl "/api/sprints/2026-01-07/2026-01-20/metrics?force_refresh=true" &
done
```

## Proposed Solutions

### Option A: rack-attack Gem (Recommended)

```ruby
# Gemfile
gem 'rack-attack'

# config/initializers/rack_attack.rb
Rack::Attack.throttle("api/ip", limit: 100, period: 1.minute) do |req|
  req.ip if req.path.start_with?("/api")
end

Rack::Attack.throttle("force_refresh/ip", limit: 5, period: 1.hour) do |req|
  req.ip if req.path.include?("/metrics") && req.params["force_refresh"] == "true"
end
```

| Aspect | Assessment |
|--------|------------|
| Pros | Industry standard, flexible rules |
| Cons | Additional dependency |
| Effort | Small |
| Risk | Low |

### Option B: Rails Built-in Rate Limiting (Rails 8)

Use Rails 8 native rate limiting if available.

| Aspect | Assessment |
|--------|------------|
| Pros | No extra dependency |
| Cons | Less flexible |
| Effort | Small |
| Risk | Low |

## Recommended Action

_To be filled during triage_

## Technical Details

**Affected Files**:
- `Gemfile`
- New: `config/initializers/rack_attack.rb`

## Acceptance Criteria

- [ ] API endpoints rate limited (100 req/min default)
- [ ] force_refresh limited (5 req/hour per IP)
- [ ] Rate limit headers returned (X-RateLimit-*)
- [ ] 429 response when limit exceeded

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-22 | Identified by security-sentinel and performance-oracle agents | No rate limiting |

## Resources

- PR #2: https://github.com/esoxjem/OpenDXI/pull/2
- rack-attack: https://github.com/rack/rack-attack
