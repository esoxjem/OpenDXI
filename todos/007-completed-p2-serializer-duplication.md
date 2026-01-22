# Serializer Dimension Scores Duplication

---
status: completed
priority: p2
issue_id: "007"
tags: [code-review, rails, dry]
dependencies: []
---

## Problem Statement

The `serialize_dimension_scores` method is duplicated verbatim in all three serializers, violating DRY and creating maintenance burden.

**Why it matters**: Bug fixes must be applied in three places. Field mapping changes require coordinated updates. Code review overhead increased.

## Findings

### Evidence from kieran-rails-reviewer and pattern-recognition-specialist agents:

**Identical implementation in 3 files**:

1. `api/app/serializers/metrics_response_serializer.rb` (lines 51-61)
2. `api/app/serializers/sprint_history_serializer.rb` (lines 30-40)
3. `api/app/serializers/developer_history_serializer.rb` (lines 51-61)

```ruby
def serialize_dimension_scores(scores)
  return nil unless scores
  {
    review_speed: scores["review_turnaround"] || scores[:review_turnaround] || 0.0,
    cycle_time: scores["cycle_time"] || scores[:cycle_time] || 0.0,
    pr_size: scores["pr_size"] || scores[:pr_size] || 0.0,
    review_coverage: scores["review_coverage"] || scores[:review_coverage] || 0.0,
    commit_frequency: scores["commit_frequency"] || scores[:commit_frequency] || 0.0
  }
end
```

**Total duplicated lines**: 33 lines (11 lines x 3 files)

## Proposed Solutions

### Option A: Extract to Module (Recommended)

```ruby
# api/app/serializers/concerns/dimension_score_serializable.rb
module DimensionScoreSerializable
  def serialize_dimension_scores(scores)
    return nil unless scores
    {
      review_speed: scores["review_turnaround"] || scores[:review_turnaround] || 0.0,
      cycle_time: scores["cycle_time"] || scores[:cycle_time] || 0.0,
      pr_size: scores["pr_size"] || scores[:pr_size] || 0.0,
      review_coverage: scores["review_coverage"] || scores[:review_coverage] || 0.0,
      commit_frequency: scores["commit_frequency"] || scores[:commit_frequency] || 0.0
    }
  end
end

# In each serializer
class MetricsResponseSerializer
  include DimensionScoreSerializable
  ...
end
```

| Aspect | Assessment |
|--------|------------|
| Pros | Standard Rails pattern, single source of truth |
| Cons | One more file |
| Effort | Small |
| Risk | None |

### Option B: Base Serializer Class

Create `BaseSerializer` with shared methods.

| Aspect | Assessment |
|--------|------------|
| Pros | OOP approach |
| Cons | May force unwanted inheritance |
| Effort | Small |
| Risk | Low |

## Recommended Action

_To be filled during triage_

## Technical Details

**Affected Files**:
- `api/app/serializers/metrics_response_serializer.rb`
- `api/app/serializers/sprint_history_serializer.rb`
- `api/app/serializers/developer_history_serializer.rb`
- New: `api/app/serializers/concerns/dimension_score_serializable.rb`

## Acceptance Criteria

- [x] Single implementation of `serialize_dimension_scores`
- [x] All serializers produce identical output
- [x] Tests pass

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-22 | Identified by kieran-rails-reviewer agent | 33 lines duplicated |

## Resources

- PR #2: https://github.com/esoxjem/OpenDXI/pull/2
