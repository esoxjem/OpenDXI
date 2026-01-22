# Date::Error Not Handled in API Controllers

---
status: completed
priority: p1
issue_id: "004"
tags: [code-review, security, data-integrity, rails]
dependencies: []
---

## Problem Statement

`Date.parse` on user input can raise `Date::Error` which is not caught by the existing `rescue_from ArgumentError` handler, causing 500 errors instead of 400 Bad Request.

**Why it matters**: Invalid date parameters return 500 Internal Server Error, which indicates a bug rather than invalid input. This confuses users and logging/monitoring systems.

## Findings

### Evidence from security-sentinel and data-integrity-guardian agents:

**File**: `api/app/controllers/api/sprints_controller.rb`
**Lines**: 22-23

```ruby
def metrics
  start_date = Date.parse(params[:start_date])
  end_date = Date.parse(params[:end_date])
```

**File**: `api/app/controllers/api/base_controller.rb`
**Lines**: 10-11

```ruby
rescue_from ActionController::ParameterMissing, with: :bad_request
rescue_from ArgumentError, with: :bad_request
# Date::Error NOT handled!
```

**Test case**: `GET /api/sprints/invalid/date/metrics` returns 500 instead of 400.

## Proposed Solutions

### Option A: Add Date::Error Handler (Recommended)

```ruby
# In api/app/controllers/api/base_controller.rb
rescue_from Date::Error, with: :bad_request
```

| Aspect | Assessment |
|--------|------------|
| Pros | Simple one-line fix |
| Cons | None |
| Effort | Trivial |
| Risk | None |

### Option B: Wrap Date Parsing with Explicit Error Handling

```ruby
def parse_date_param(param_name)
  Date.parse(params[param_name])
rescue Date::Error
  raise ArgumentError, "Invalid date format for #{param_name}"
end
```

| Aspect | Assessment |
|--------|------------|
| Pros | More descriptive error messages |
| Cons | More code |
| Effort | Small |
| Risk | None |

## Recommended Action

_To be filled during triage_

## Technical Details

**Affected Files**:
- `api/app/controllers/api/base_controller.rb`

## Acceptance Criteria

- [x] `GET /api/sprints/invalid/date/metrics` returns 400, not 500
- [x] Error response includes helpful message
- [x] Test added for invalid date parameter

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-22 | Identified by security-sentinel and data-integrity-guardian agents | Date::Error not subclass of ArgumentError |

## Resources

- PR #2: https://github.com/esoxjem/OpenDXI/pull/2
- File: `api/app/controllers/api/base_controller.rb`
