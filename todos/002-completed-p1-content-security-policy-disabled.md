# Content Security Policy Disabled

---
status: completed
priority: p1
issue_id: "002"
tags: [code-review, security, rails, critical]
dependencies: []
---

## Problem Statement

The Content Security Policy (CSP) is completely commented out, leaving the application vulnerable to XSS attacks that CSP would mitigate.

**Why it matters**: CSP is a critical defense-in-depth layer against cross-site scripting attacks. Without it, any XSS vulnerability becomes fully exploitable.

## Findings

### Evidence from security-sentinel agent:

**File**: `api/config/initializers/content_security_policy.rb`
**Lines**: 1-30 (entire file is commented out)

```ruby
# Rails.application.configure do
#   config.content_security_policy do |policy|
#     policy.default_src :self, :https
#     ...
#   end
# end
```

## Proposed Solutions

### Option A: Enable CSP with Tailwind/Chart.js Compatibility (Recommended)

```ruby
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :data
    policy.img_src     :self, :data, "https://github.com", "https://avatars.githubusercontent.com"
    policy.object_src  :none
    policy.script_src  :self, "https://cdn.jsdelivr.net"  # For Chart.js CDN
    policy.style_src   :self, :unsafe_inline  # Required for Tailwind
    policy.connect_src :self
  end

  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w[script-src]
end
```

| Aspect | Assessment |
|--------|------------|
| Pros | Strong XSS protection, allows Tailwind |
| Cons | May need tuning for Chart.js |
| Effort | Small |
| Risk | Low (start with report-only mode) |

### Option B: Report-Only Mode First

Enable CSP in report-only mode to identify violations before enforcing.

| Aspect | Assessment |
|--------|------------|
| Pros | No risk of breaking functionality |
| Cons | Delayed protection |
| Effort | Small |
| Risk | None |

## Recommended Action

_To be filled during triage_

## Technical Details

**Affected Files**:
- `api/config/initializers/content_security_policy.rb`

**Dependencies**: May need to update importmap or Chart.js loading pattern.

## Acceptance Criteria

- [x] CSP enabled in production
- [x] No console errors from CSP violations in normal usage
- [x] Chart.js and Tailwind work correctly
- [x] XSS test payloads blocked

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-22 | Identified by security-sentinel agent | CSP completely disabled |

## Resources

- PR #2: https://github.com/esoxjem/OpenDXI/pull/2
- Rails Security Guide: https://guides.rubyonrails.org/security.html#content-security-policy-header
