# No API Schema/Documentation (OpenAPI)

---
status: pending
priority: p3
issue_id: "013"
tags: [code-review, api, documentation]
dependencies: []
---

## Problem Statement

No OpenAPI/Swagger schema exists for the API endpoints. Agents and external consumers cannot programmatically discover available endpoints or request/response formats.

**Why it matters**: API consumers must manually discover endpoints. No generated client SDKs possible. Poor developer experience for integrations.

## Findings

### Evidence from agent-native-reviewer agent:

**Missing**: `/api/openapi.json` or `/api/swagger.json`

**Current API endpoints** (undocumented):
- GET /api/health
- GET /api/config
- GET /api/sprints
- GET /api/sprints/:start_date/:end_date/metrics
- GET /api/sprints/history
- GET /api/developers/:name/history

## Proposed Solutions

### Option A: rswag Gem (Recommended)

```ruby
# Gemfile
gem 'rswag-api'
gem 'rswag-ui'
gem 'rswag-specs', group: [:development, :test]

# Then generate OpenAPI spec from request specs
```

| Aspect | Assessment |
|--------|------------|
| Pros | Spec-driven, auto-generated UI |
| Cons | Requires writing specs |
| Effort | Medium |
| Risk | None |

### Option B: Manual OpenAPI YAML

Write `openapi.yaml` manually and serve it.

| Aspect | Assessment |
|--------|------------|
| Pros | Quick to start |
| Cons | Must keep in sync manually |
| Effort | Medium |
| Risk | Drift from actual API |

## Recommended Action

_To be filled during triage_

## Technical Details

**Affected Files**:
- `Gemfile`
- New: `swagger/` directory
- New: `spec/requests/api/` specs

## Acceptance Criteria

- [ ] GET /api/docs serves Swagger UI
- [ ] GET /api/openapi.json returns valid OpenAPI 3.0 spec
- [ ] All endpoints documented with request/response examples

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-22 | Identified by agent-native-reviewer agent | No API schema |

## Resources

- PR #2: https://github.com/esoxjem/OpenDXI/pull/2
- rswag: https://github.com/rswag/rswag
