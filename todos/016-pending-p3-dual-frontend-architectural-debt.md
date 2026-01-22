# Dual Frontend Architecture (React + Hotwire)

---
status: pending
priority: p3
issue_id: "016"
tags: [code-review, architecture, decision-required]
dependencies: []
---

## Problem Statement

The project maintains two complete frontends: React/Next.js (`frontend/`) and Rails Hotwire (`api/app/views/`). This creates maintenance burden and architectural confusion.

**Why it matters**: Double the frontend code to maintain. Serializers exist solely to match "FastAPI contract". Risk of feature drift between frontends.

## Findings

### Evidence from dhh-rails-reviewer agent:

**React Frontend** (`frontend/`):
- 27 TypeScript files
- TanStack Query hooks (duplicates Rails caching)
- Type definitions mirroring serializers
- Node.js build step required

**Hotwire Frontend** (`api/app/views/`):
- Complete dashboard implementation
- No build step required
- Uses same data as React frontend

**Serializers comment** (`metrics_response_serializer.rb:4`):
```ruby
# Serializes Sprint data to match the FastAPI MetricsResponse contract.
```

## Proposed Solutions

### Option A: Keep Both (Status Quo)

Maintain React for external consumers, Hotwire for admin/internal.

| Aspect | Assessment |
|--------|------------|
| Pros | Flexibility, gradual migration |
| Cons | Double maintenance |
| Effort | Ongoing |
| Risk | Feature drift |

### Option B: Remove React Frontend

Use Hotwire dashboard exclusively, simplify architecture.

| Aspect | Assessment |
|--------|------------|
| Pros | Simpler, single source of truth |
| Cons | Loses React investment |
| Effort | Medium |
| Risk | Low if Hotwire meets needs |

### Option C: Remove Hotwire Views

Keep React frontend, Rails becomes pure API.

| Aspect | Assessment |
|--------|------------|
| Pros | Clear separation |
| Cons | Loses Rails view simplicity |
| Effort | Small |
| Risk | Low |

## Recommended Action

_To be filled during triage - requires product decision_

## Technical Details

**Affected Directories**:
- `frontend/` (React/Next.js)
- `api/app/views/` (Hotwire)
- `api/app/serializers/` (API contract)

## Acceptance Criteria

_Depends on chosen direction_

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-22 | Identified by dhh-rails-reviewer agent | Dual frontend maintenance |

## Resources

- PR #2: https://github.com/esoxjem/OpenDXI/pull/2
- DHH on Hotwire: https://hotwired.dev/
