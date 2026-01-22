# View Parameter Template Injection Risk

---
status: completed
priority: p1
issue_id: "003"
tags: [code-review, security, rails, critical]
dependencies: []
---

## Problem Statement

The `@view` parameter from user input is used directly to construct partial template paths without validation, creating a potential path traversal or template injection risk.

**Why it matters**: An attacker could manipulate the view parameter to render unintended templates or cause denial of service via missing template errors.

## Findings

### Evidence from security-sentinel agent:

**File**: `api/app/controllers/dashboard_controller.rb`
**Lines**: 7, 16

```ruby
@view = params[:view] || "team"
```

**File**: `api/app/views/dashboard/show.html.erb`
**Line**: 25

```erb
<%= render "dashboard/#{@view}_tab", sprint: @sprint, ... %>
```

**Attack Vector**: `GET /dashboard?view=../../../etc/passwd` or `GET /dashboard?view=nonexistent` could cause unexpected behavior.

## Proposed Solutions

### Option A: Whitelist Allowed Values (Recommended)

```ruby
ALLOWED_VIEWS = %w[team developers].freeze

def show
  @view = ALLOWED_VIEWS.include?(params[:view]) ? params[:view] : "team"
end
```

| Aspect | Assessment |
|--------|------------|
| Pros | Simple, secure, explicit |
| Cons | Must update when adding new views |
| Effort | Small |
| Risk | None |

### Option B: Use Rails Enum Pattern

Define views as a constant and validate against it.

| Aspect | Assessment |
|--------|------------|
| Pros | More Rails-idiomatic |
| Cons | Slightly more complex |
| Effort | Small |
| Risk | None |

## Recommended Action

_To be filled during triage_

## Technical Details

**Affected Files**:
- `api/app/controllers/dashboard_controller.rb`
- `api/app/views/dashboard/show.html.erb`
- `api/app/views/dashboard/_metrics.html.erb`

## Acceptance Criteria

- [x] Only "team" and "developers" views allowed
- [x] Invalid view parameter returns default "team"
- [x] No template injection possible
- [x] Test added for invalid view parameter

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-22 | Identified by security-sentinel agent | User input in template path |

## Resources

- PR #2: https://github.com/esoxjem/OpenDXI/pull/2
- File: `api/app/controllers/dashboard_controller.rb:7`
