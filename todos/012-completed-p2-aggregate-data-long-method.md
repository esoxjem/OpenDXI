# GithubService.aggregate_data is 127 Lines

---
status: completed
priority: p2
issue_id: "012"
tags: [code-review, rails, refactoring]
dependencies: []
---

## Problem Statement

The `aggregate_data` method in GithubService is 127 lines with 6+ responsibilities, making it difficult to test, understand, and maintain.

**Why it matters**: Long methods increase cognitive load, make debugging harder, and reduce testability of individual behaviors.

## Findings

### Evidence from pattern-recognition-specialist agent:

**File**: `api/app/services/github_service.rb`
**Lines**: 235-362 (127 lines)

**Responsibilities identified**:
1. Processing commits (lines 249-261)
2. Processing PRs (lines 264-276)
3. Processing reviews (lines 294-314)
4. Calculating averages and DXI scores (lines 317-338)
5. Building daily activity (line 344)
6. Building summary (lines 347-354)

## Proposed Solutions

### Option A: Extract Private Methods (Recommended)

```ruby
def aggregate_data(prs, commits, since_date, until_date)
  developer_stats = initialize_developer_stats
  daily_stats = initialize_daily_stats

  process_commits(commits, developer_stats, daily_stats, since_date, until_date)
  process_prs(prs, developer_stats, daily_stats, since_date, until_date)

  developers = build_developers_with_scores(developer_stats)
  daily_activity = build_daily_activity(daily_stats, since_date, until_date)
  summary = build_summary(developers)

  {
    "developers" => developers,
    "daily_activity" => daily_activity,
    "summary" => summary,
    "team_dimension_scores" => DxiCalculator.team_dimension_scores(developers)
  }
end

private

def process_commits(commits, developer_stats, daily_stats, since_date, until_date)
  # ... extracted logic
end

def process_prs(prs, developer_stats, daily_stats, since_date, until_date)
  # ... extracted logic
end
```

| Aspect | Assessment |
|--------|------------|
| Pros | Readable, testable methods |
| Cons | More methods to maintain |
| Effort | Medium |
| Risk | Low |

### Option B: Extract to DataAggregator Class

Create a separate class for aggregation logic.

| Aspect | Assessment |
|--------|------------|
| Pros | Single responsibility per class |
| Cons | More files |
| Effort | Medium |
| Risk | Low |

## Recommended Action

_To be filled during triage_

## Technical Details

**Affected Files**:
- `api/app/services/github_service.rb`

## Acceptance Criteria

- [x] No method longer than 30 lines
- [x] Each extracted method has clear responsibility
- [x] Tests pass
- [x] No functional changes to output

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-22 | Identified by pattern-recognition-specialist agent | 127 line method |

## Resources

- PR #2: https://github.com/esoxjem/OpenDXI/pull/2
- File: `api/app/services/github_service.rb:235-362`
