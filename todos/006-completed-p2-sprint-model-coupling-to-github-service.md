# Sprint Model Coupling to GithubService

---
status: completed
priority: p2
issue_id: "006"
tags: [code-review, architecture, rails]
dependencies: []
---

## Problem Statement

The `Sprint` model directly calls `GithubService.fetch_sprint_data`, violating the Dependency Inversion Principle and making the model difficult to test in isolation.

**Why it matters**: Testing Sprint model requires mocking GithubService. Cannot swap data sources without model changes. Blurs separation between data access and business logic.

## Findings

### Evidence from architecture-strategist agent:

**File**: `api/app/models/sprint.rb`
**Line**: 30

```ruby
def find_or_fetch!(start_date, end_date, force: false)
  ...
  data = GithubService.fetch_sprint_data(start_date, end_date)  # Direct coupling
  ...
end
```

**Coupling Severity**: HIGH
- Model depends on Service
- Cannot inject alternative data fetcher
- Testing requires GithubService mock

## Proposed Solutions

### Option A: Extract to SprintLoader Service (Recommended)

```ruby
# api/app/services/sprint_loader.rb
class SprintLoader
  def initialize(fetcher: GithubService)
    @fetcher = fetcher
  end

  def load(start_date, end_date, force: false)
    sprint = Sprint.find_by_dates(start_date, end_date)
    return sprint if sprint && !force

    data = @fetcher.fetch_sprint_data(start_date, end_date)
    Sprint.upsert_by_dates!(start_date, end_date, data)
  end
end

# Usage in controller
SprintLoader.new.load(start_date, end_date, force: force_refresh)
```

| Aspect | Assessment |
|--------|------------|
| Pros | Testable, swappable fetcher, clean separation |
| Cons | More files, breaks existing API |
| Effort | Medium |
| Risk | Low |

### Option B: Dependency Injection via Block

```ruby
def find_or_fetch!(start_date, end_date, force: false, &fetcher)
  fetcher ||= -> (s, e) { GithubService.fetch_sprint_data(s, e) }
  ...
end
```

| Aspect | Assessment |
|--------|------------|
| Pros | Minimal change, testable |
| Cons | Unusual pattern |
| Effort | Small |
| Risk | Low |

## Recommended Action

_To be filled during triage_

## Technical Details

**Affected Files**:
- `api/app/models/sprint.rb`
- `api/app/controllers/dashboard_controller.rb`
- `api/app/controllers/api/sprints_controller.rb`

## Acceptance Criteria

- [x] Sprint model can be tested without GithubService
- [x] Controllers updated to use new pattern (via existing find_or_fetch! API)
- [x] Existing functionality preserved

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-22 | Identified by architecture-strategist agent | DIP violation |

## Resources

- PR #2: https://github.com/esoxjem/OpenDXI/pull/2
- File: `api/app/models/sprint.rb:30`
