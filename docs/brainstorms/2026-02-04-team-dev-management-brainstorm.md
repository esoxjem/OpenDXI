# Team & Developer Management Brainstorm

**Date:** 2026-02-04
**Status:** Ready for planning

## What We're Building

A system for managing which GitHub org developers appear on the dashboard, organizing them into teams, and filtering the dashboard by team. This adds three connected capabilities to OpenDXI:

1. **Org Member Discovery** — Fetch all members from the GitHub org and display them in Settings
2. **Developer Visibility Control** — Owner toggles which devs' metrics appear on the dashboard (global setting)
3. **Team Grouping** — Create teams (import from GitHub Teams API + manual), assign devs to teams (many-to-many)
4. **Team Filtering on Dashboard** — Filter the entire Team Overview tab (KPIs, charts, radar, leaderboard) by team via URL query param

## Why This Approach

### Source of truth: GitHub Org API
- The org member list comes from the GitHub API (`GET /orgs/{org}/members`), not from sprint data or the Users table
- This ensures we see ALL org members, not just those with recent activity
- Cached on first Settings visit, refreshable with a button click

### Visibility = display-time filter, not data exclusion
- All sprint data is still fetched and stored for all org members
- Hidden devs are filtered out at the API response level (or frontend)
- Preserves data history — toggling a dev back on instantly restores their metrics
- Dashboard indicates hidden devs exist (e.g., "Showing 8 of 12 org members")

### Teams: hybrid import + manual
- Import teams from GitHub Teams API as a flat list (ignore nesting hierarchy)
- Allow creating custom teams manually
- Allow manual overrides (add/remove devs from imported teams)
- Many-to-many: a dev can belong to multiple teams

### Dashboard filtering: full-tab scope with URL params
- Team filter dropdown on the Team Overview tab
- When a team is selected, ALL components filter: KPI cards, activity chart, radar chart, AND leaderboard
- Uses URL query param (`?team=backend`) — shareable and bookmarkable
- Follows existing URL param pattern (`?view=team`, `?sprint=...`, `?developer=name`)

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Org member source | GitHub API (`/orgs/{org}/members`) | Complete list, not just active devs |
| Fetch timing | Cached, manual refresh button | Balance freshness vs. API calls |
| Visibility scope | Global (owner-controlled) | Consistent view across all users |
| Hidden dev data | Keep data, filter at display time | Reversible, no data loss |
| Hidden dev indicator | Show "X of Y org members" | Transparency without clutter |
| Team source | GitHub Teams API + manual creation | Flexibility with real org structure |
| Team nesting | Flat import (ignore hierarchy) | YAGNI — nesting adds complexity |
| Dev-team relationship | Many-to-many | Reflects cross-functional reality |
| Settings UI layout | Unified view: org members list with inline visibility toggle + team assignment | Single page, less navigation |
| Team filter scope | Full Team Overview tab (KPIs, charts, radar, leaderboard) | Consistent filtered view |
| Team filter UX | Dropdown above leaderboard, URL query param | Shareable, follows existing patterns |

## Data Model (Conceptual)

### New tables needed

```
developers
  - id
  - github_login (unique, from org API)
  - github_id (unique)
  - name
  - avatar_url
  - visible (boolean, default: true)
  - timestamps

teams
  - id
  - name (unique)
  - github_team_slug (nullable, for imported teams)
  - timestamps

team_memberships (join table)
  - id
  - team_id (FK)
  - developer_id (FK)
  - unique index on [team_id, developer_id]
  - timestamps
```

### Why a separate `developers` table (not reuse `users`)?
- `users` = people who can log into the app (access control)
- `developers` = GitHub org members whose metrics are tracked (data/display concern)
- These are different concepts: a bot could be a "developer" but not a "user"; an owner might be a "user" but not actively contributing code
- Keeping them separate avoids conflating access control with metric tracking

## API Endpoints (Conceptual)

### Settings (owner-only)
- `GET /api/org_members` — Fetch org members from GitHub (cached)
- `POST /api/org_members/refresh` — Force refresh from GitHub
- `GET /api/developers` — List developers with visibility + team assignments (already exists, needs enhancement)
- `PATCH /api/developers/:id` — Toggle visibility
- `GET /api/teams` — List teams
- `POST /api/teams` — Create team (manual or import)
- `POST /api/teams/import` — Import teams from GitHub Teams API
- `PATCH /api/teams/:id` — Update team (name, members)
- `DELETE /api/teams/:id` — Delete team

### Dashboard (all users)
- `GET /api/sprints/:start/:end/metrics?team=slug` — Existing endpoint, add team filter param
- Filtering logic: if `team` param present, filter `developers` array to only those in the specified team, recalculate summary/team_dimension_scores for the filtered set

## Open Questions

1. **Should the existing `/api/developers` endpoint be repurposed or should we create a new one?** — Currently returns developer names from sprint data. The new "developers" concept is org-member based.
2. **Refresh button for org members — should it also sync GitHub Teams?** — Probably yes, single "Sync from GitHub" action.
3. **What happens when a GitHub team member isn't in the org anymore?** — Probably mark as inactive but keep team membership for historical data.

## Scope Boundaries (NOT building)

- Per-user dashboard preferences (filtering is global via owner settings)
- Nested team hierarchies
- Team-level DXI scoring or team comparison views (could be a future feature)
- Automatic team sync on a schedule (manual refresh only for now)
