# Private Method Access via send()

---
status: pending
priority: p2
issue_id: "010"
tags: [code-review, rails, encapsulation]
dependencies: []
---

## Problem Statement

`DashboardController` uses `send(:empty_response)` to call a private method on `GithubService`, violating encapsulation and indicating a design issue.

**Why it matters**: Using `send` to bypass visibility is a code smell. If `empty_response` is needed outside GithubService, it should be public or extracted.

## Findings

### Evidence from kieran-rails-reviewer agent:

**File**: `api/app/controllers/dashboard_controller.rb`
**Lines**: 56-60

```ruby
def create_placeholder_sprint(start_date, end_date)
  Sprint.find_or_create_by!(start_date: start_date, end_date: end_date) do |s|
    s.data = GithubService.send(:empty_response)  # <- Calling private method
  end
end
```

**File**: `api/app/services/github_service.rb`
**Lines**: 166-179 (private method)

```ruby
private

def empty_response
  {
    "developers" => [],
    "daily_activity" => [],
    ...
  }
end
```

## Proposed Solutions

### Option A: Make empty_response Public (Recommended)

```ruby
class GithubService
  class << self
    def empty_response
      {
        "developers" => [],
        ...
      }
    end
  end
end
```

| Aspect | Assessment |
|--------|------------|
| Pros | Simple, explicit API |
| Cons | Exposes internal structure |
| Effort | Trivial |
| Risk | None |

### Option B: Extract to Constant/Module

```ruby
module SprintData
  EMPTY = {
    "developers" => [],
    "daily_activity" => [],
    ...
  }.freeze
end

# Usage
s.data = SprintData::EMPTY.deep_dup
```

| Aspect | Assessment |
|--------|------------|
| Pros | Reusable, clear ownership |
| Cons | New module |
| Effort | Small |
| Risk | None |

## Recommended Action

_To be filled during triage_

## Technical Details

**Affected Files**:
- `api/app/controllers/dashboard_controller.rb`
- `api/app/services/github_service.rb`

## Acceptance Criteria

- [ ] No `send` calls to private methods
- [ ] Empty response structure available to controller
- [ ] Tests pass

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-22 | Identified by kieran-rails-reviewer agent | Encapsulation violation |

## Resources

- PR #2: https://github.com/esoxjem/OpenDXI/pull/2
- File: `api/app/controllers/dashboard_controller.rb:58`
