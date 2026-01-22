# Missing GET /api/developers Endpoint

---
status: pending
priority: p3
issue_id: "015"
tags: [code-review, api, agent-native]
dependencies: []
---

## Problem Statement

No endpoint exists to list all known developers. Consumers must fetch full sprint metrics just to get developer names.

**Why it matters**: API consumers cannot enumerate developers without loading heavy metrics payload. Inefficient for autocomplete, dropdowns, or agent queries.

## Findings

### Evidence from agent-native-reviewer agent:

**File**: `api/config/routes.rb`
**Lines**: 14-15 (only history endpoint exists)

```ruby
# Developer endpoints
get "developers/:name/history", to: "developers#history"
# Missing: get "developers", to: "developers#index"
```

**Current workaround**: Fetch `/api/sprints/:start/:end/metrics` and extract `developers[].developer` names.

## Proposed Solutions

### Option A: Add Index Endpoint (Recommended)

```ruby
# routes.rb
get "developers", to: "developers#index"

# developers_controller.rb
def index
  sprints = Sprint.order(start_date: :desc).limit(params[:sprint_count] || 6)
  developers = sprints.flat_map(&:developers)
                      .map { |d| d["developer"] }
                      .uniq
                      .sort

  render json: { developers: developers }
end
```

| Aspect | Assessment |
|--------|------------|
| Pros | Lightweight, agent-friendly |
| Cons | Minor additional endpoint |
| Effort | Small |
| Risk | None |

## Recommended Action

_To be filled during triage_

## Technical Details

**Affected Files**:
- `api/config/routes.rb`
- `api/app/controllers/api/developers_controller.rb`

## Acceptance Criteria

- [ ] GET /api/developers returns list of developer names
- [ ] Optional `sprint_count` parameter
- [ ] Response format: `{ "developers": ["name1", "name2", ...] }`

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-22 | Identified by agent-native-reviewer agent | Missing enumeration endpoint |

## Resources

- PR #2: https://github.com/esoxjem/OpenDXI/pull/2
