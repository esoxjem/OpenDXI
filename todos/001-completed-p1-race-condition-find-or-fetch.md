# Race Condition in Sprint.find_or_fetch!

---
status: completed
priority: p1
issue_id: "001"
tags: [code-review, data-integrity, rails, critical]
dependencies: []
---

## Problem Statement

The `Sprint.find_or_fetch!` method has a race condition that can cause `ActiveRecord::RecordNotUnique` exceptions when multiple concurrent requests try to create the same sprint.

**Why it matters**: Users making concurrent requests (e.g., two browser tabs) will see 500 errors instead of getting data. In production, this could affect multiple users during peak usage.

## Findings

### Evidence from data-integrity-guardian agent:

**File**: `api/app/models/sprint.rb`
**Lines**: 23-39

```ruby
def find_or_fetch!(start_date, end_date, force: false)
  sprint = find_by_dates(start_date, end_date)  # <- Read
  return sprint if sprint && !force

  data = GithubService.fetch_sprint_data(start_date, end_date)  # <- Long operation (5+ seconds)

  if sprint
    sprint.update!(data: data)
  else
    sprint = create!(start_date: start_date, end_date: end_date, data: data)  # <- Create fails
  end
end
```

**Race Condition Scenario**:
1. Thread A calls `find_or_fetch!("2026-01-07", "2026-01-20")`
2. Thread A finds no existing sprint, starts fetching (takes 5+ seconds)
3. Thread B calls same method, also finds no sprint
4. Thread A completes, calls `create!`
5. Thread B completes, calls `create!` -> **RecordNotUnique exception**

## Proposed Solutions

### Option A: Transaction with Retry (Recommended)

Wrap in transaction and retry on unique constraint violation.

```ruby
def find_or_fetch!(start_date, end_date, force: false)
  start_date = Date.parse(start_date.to_s)
  end_date = Date.parse(end_date.to_s)

  transaction do
    sprint = find_by_dates(start_date, end_date)
    return sprint if sprint && !force

    data = GithubService.fetch_sprint_data(start_date, end_date)

    if sprint
      sprint.update!(data: data)
      sprint
    else
      create!(start_date: start_date, end_date: end_date, data: data)
    end
  end
rescue ActiveRecord::RecordNotUnique
  find_by_dates(start_date, end_date)
end
```

| Aspect | Assessment |
|--------|------------|
| Pros | Simple, handles race gracefully |
| Cons | Second request may return stale data |
| Effort | Small |
| Risk | Low |

### Option B: Advisory Lock

Use database advisory lock during fetch.

| Aspect | Assessment |
|--------|------------|
| Pros | Prevents duplicate API calls |
| Cons | More complex, SQLite compatibility concerns |
| Effort | Medium |
| Risk | Medium |

## Recommended Action

_To be filled during triage_

## Technical Details

**Affected Files**:
- `api/app/models/sprint.rb`

**Database**: Uses unique index on `[start_date, end_date]` which properly enforces constraint.

## Acceptance Criteria

- [x] Concurrent requests for same sprint do not cause 500 errors
- [x] Test added for concurrent access scenario
- [x] Error handling returns valid sprint data

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-22 | Identified by data-integrity-guardian agent | Race condition in read-modify-write pattern |

## Resources

- PR #2: https://github.com/esoxjem/OpenDXI/pull/2
- File: `api/app/models/sprint.rb:23-39`
