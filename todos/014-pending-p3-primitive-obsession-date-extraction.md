# Primitive Obsession - Date String Extraction

---
status: pending
priority: p3
issue_id: "014"
tags: [code-review, rails, refactoring]
dependencies: []
---

## Problem Statement

Repeated substring date extraction pattern `.to_s[0, 10]` appears 6 times in GithubService, which is fragile and unclear.

**Why it matters**: Unclear what `[0, 10]` means without context. Easy to make off-by-one errors. Pattern should be named.

## Findings

### Evidence from pattern-recognition-specialist agent:

**File**: `api/app/services/github_service.rb`

**Occurrences**:
- Line 109: `r["pushedAt"].to_s[0, 10] >= since_date`
- Line 118: `created_date = pr["createdAt"].to_s[0, 10]`
- Line 254: `commit_date = author["date"].to_s[0, 10]`
- Line 266: `created_date = created_at[0, 10]`
- Line 280: `merged_date = merged_at[0, 10]`
- Line 302: `review_date = submitted_at[0, 10]`

## Proposed Solutions

### Option A: Extract Helper Method (Recommended)

```ruby
def extract_date(iso_timestamp)
  iso_timestamp.to_s[0, 10]
end

# Usage
created_date = extract_date(pr["createdAt"])
```

| Aspect | Assessment |
|--------|------------|
| Pros | Clear intent, single definition |
| Cons | Minor |
| Effort | Trivial |
| Risk | None |

### Option B: Use Date.parse

```ruby
created_date = Date.parse(pr["createdAt"]).to_s
```

| Aspect | Assessment |
|--------|------------|
| Pros | More explicit parsing |
| Cons | Slightly slower |
| Effort | Trivial |
| Risk | None |

## Recommended Action

_To be filled during triage_

## Technical Details

**Affected Files**:
- `api/app/services/github_service.rb`

## Acceptance Criteria

- [ ] Single helper method for date extraction
- [ ] All 6 occurrences use the helper
- [ ] Tests pass

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-22 | Identified by pattern-recognition-specialist agent | 6 duplicate patterns |

## Resources

- PR #2: https://github.com/esoxjem/OpenDXI/pull/2
