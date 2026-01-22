# Rails 8 API Backend with Next.js Frontend

## Overview

Convert the Rails 8 monolith from a Hotwire-based full-stack app to a **JSON API backend** that serves the existing Next.js frontend. This preserves the working frontend (shadcn/ui components, TanStack Query hooks, Recharts visualizations) while replacing FastAPI with Rails for the backend.

**Key Insight**: The Rails app already has all business logic implemented (GithubService, DxiCalculator, Sprint model). We only need to add a JSON API layer on top.

---

## Problem Statement

The current migration plan replaces the entire stack (FastAPI + Next.js) with Rails + Hotwire. However:

1. **The Next.js frontend already works** - shadcn/ui components, TanStack Query caching, responsive design
2. **Team is familiar with React** - faster iteration, existing component patterns
3. **Hotwire learning curve** - time investment for similar results
4. **Existing component library** - would need to be rebuilt in ERB + Stimulus

The Rails backend is valuable (simpler than FastAPI for this use case), but the frontend switch has unclear benefits.

---

## Proposed Solution

Add an `/api` namespace to Rails that matches the existing FastAPI contract exactly. The Next.js frontend continues unchanged, just pointing to Rails instead of FastAPI.

```
┌─────────────────────┐     ┌─────────────────────┐
│   Next.js Frontend  │────▶│   Rails 8 Backend   │
│   (unchanged)       │     │   (new API layer)   │
│                     │     │                     │
│ - shadcn/ui         │     │ - /api/sprints      │
│ - TanStack Query    │     │ - /api/developers   │
│ - Recharts          │     │ - GithubService     │
│ - Framer Motion     │     │ - DxiCalculator     │
└─────────────────────┘     └─────────────────────┘
```

---

## Technical Approach

### Architecture

Rails serves JSON API only (no HTML views needed for the dashboard). The existing Hotwire views can be removed or kept for a future admin UI.

```ruby
# config/routes.rb
Rails.application.routes.draw do
  namespace :api do
    get "health", to: "health#show"
    get "config", to: "config#show"

    resources :sprints, only: [:index] do
      collection do
        get "history"
      end
    end
    get "sprints/:start_date/:end_date/metrics", to: "sprints#metrics"

    get "developers/:name/history", to: "developers#history"
  end

  # Keep root for potential admin UI later
  root "application#health_check"
end
```

### API Contract Compatibility

The Rails API must match FastAPI's response format exactly. Key mappings:

| FastAPI Key | Rails Key (Current) | Action |
|-------------|---------------------|--------|
| `daily` | `daily_activity` | Rename in serializer |
| `review_speed` | `review_turnaround` | Rename in serializer |
| `start` / `end` | `start_date` / `end_date` | Add aliases in serializer |

### Implementation Phases

#### Phase 1: API Infrastructure
- Add `rack-cors` gem for CORS support
- Create `Api::BaseController` with JSON error handling
- Configure routes under `/api` namespace
- Add request specs for contract validation

#### Phase 2: Core Endpoints
- `GET /api/health` - Health check with version
- `GET /api/config` - GitHub org configuration
- `GET /api/sprints` - Sprint list for dropdown
- `GET /api/sprints/:start/:end/metrics` - Sprint metrics (main endpoint)

#### Phase 3: History Endpoints
- `GET /api/sprints/history` - Team DXI trend data
- `GET /api/developers/:name/history` - Individual developer trends

#### Phase 4: Cleanup
- Remove or archive Hotwire views
- Remove unused JavaScript (Stimulus controllers)
- Update documentation

---

## Acceptance Criteria

### Functional Requirements
- [x] All 6 API endpoints return JSON matching FastAPI format
- [x] CORS allows requests from `localhost:3000` (dev) and production domain
- [x] `force_refresh=true` query param triggers fresh GitHub data fetch
- [x] Error responses return consistent JSON format with status codes
- [x] Sprint date calculations match existing FastAPI logic

### Non-Functional Requirements
- [ ] Response times under 200ms for cached data
- [ ] GitHub API rate limiting handled gracefully (429 response)
- [ ] No breaking changes to frontend TypeScript types

### Quality Gates
- [ ] Request specs cover all endpoints with contract assertions
- [ ] Frontend runs against Rails backend without code changes
- [ ] All existing frontend features work (KPIs, charts, leaderboard, tabs)

---

## Files to Create/Modify

### New Files

```
opendxi_rails/
├── app/
│   ├── controllers/
│   │   └── api/
│   │       ├── base_controller.rb          # API base with error handling
│   │       ├── health_controller.rb        # GET /api/health
│   │       ├── config_controller.rb        # GET /api/config
│   │       ├── sprints_controller.rb       # Sprint endpoints
│   │       └── developers_controller.rb    # Developer endpoints
│   └── serializers/
│       ├── sprint_serializer.rb            # Sprint list item
│       ├── metrics_response_serializer.rb  # Full metrics response
│       ├── developer_metrics_serializer.rb # Individual developer
│       └── sprint_history_serializer.rb    # History entry
├── config/
│   └── initializers/
│       └── cors.rb                         # CORS configuration
└── spec/
    └── requests/
        └── api/
            ├── health_spec.rb
            ├── config_spec.rb
            ├── sprints_spec.rb
            └── developers_spec.rb
```

### Modified Files

| File | Changes |
|------|---------|
| `Gemfile` | Add `rack-cors` gem |
| `config/routes.rb` | Add `/api` namespace |
| `app/controllers/application_controller.rb` | Skip browser check for API |

### Files to Remove (Optional)

| File/Directory | Reason |
|----------------|--------|
| `app/views/dashboard/` | Hotwire views no longer needed |
| `app/views/developers/` | Hotwire views no longer needed |
| `app/views/sprints/` | Hotwire views no longer needed |
| `app/javascript/controllers/radar_chart_controller.js` | Stimulus no longer needed |

---

## MVP Implementation

### api/base_controller.rb

```ruby
# app/controllers/api/base_controller.rb
module Api
  class BaseController < ActionController::API
    rescue_from ActiveRecord::RecordNotFound, with: :not_found
    rescue_from ActionController::ParameterMissing, with: :bad_request
    rescue_from GithubService::GitHubApiError, with: :github_error
    rescue_from GithubService::GhCliNotFound, with: :gh_cli_missing

    private

    def not_found(exception)
      render json: { error: "not_found", detail: exception.message }, status: :not_found
    end

    def bad_request(exception)
      render json: { error: "bad_request", detail: exception.message }, status: :bad_request
    end

    def github_error(exception)
      render json: { error: "github_api_error", detail: exception.message }, status: :bad_gateway
    end

    def gh_cli_missing(exception)
      render json: { error: "configuration_error", detail: exception.message }, status: :service_unavailable
    end
  end
end
```

### api/sprints_controller.rb

```ruby
# app/controllers/api/sprints_controller.rb
module Api
  class SprintsController < BaseController
    # GET /api/sprints
    def index
      sprints = Sprint.available_sprints
      render json: { sprints: sprints.map { |s| serialize_sprint_item(s) } }
    end

    # GET /api/sprints/:start_date/:end_date/metrics
    def metrics
      start_date = Date.parse(params[:start_date])
      end_date = Date.parse(params[:end_date])
      force_refresh = params[:force_refresh] == "true"

      sprint = Sprint.find_or_fetch!(start_date, end_date, force: force_refresh)

      render json: MetricsResponseSerializer.new(sprint).as_json
    rescue ArgumentError => e
      render json: { error: "invalid_date", detail: e.message }, status: :bad_request
    end

    # GET /api/sprints/history
    def history
      count = (params[:count] || 6).to_i.clamp(1, 12)
      sprints = Sprint.order(start_date: :desc).limit(count)

      render json: {
        history: sprints.map { |s| SprintHistorySerializer.new(s).as_json }
      }
    end

    private

    def serialize_sprint_item(sprint)
      {
        label: sprint.label,
        value: "#{sprint.start_date}|#{sprint.end_date}",
        start: sprint.start_date.to_s,
        end: sprint.end_date.to_s,
        is_current: sprint.current?
      }
    end
  end
end
```

### metrics_response_serializer.rb

```ruby
# app/serializers/metrics_response_serializer.rb
class MetricsResponseSerializer
  def initialize(sprint)
    @sprint = sprint
  end

  def as_json
    {
      developers: @sprint.developers.map { |d| serialize_developer(d) },
      daily: @sprint.daily_activity,  # Note: 'daily' not 'daily_activity'
      summary: @sprint.summary,
      team_dimension_scores: serialize_dimension_scores(@sprint.team_dimension_scores)
    }
  end

  private

  def serialize_developer(dev)
    {
      developer: dev["github_login"],
      commits: dev["commits"],
      prs_opened: dev["prs_opened"],
      prs_merged: dev["prs_merged"],
      reviews_given: dev["reviews_given"],
      lines_added: dev["lines_added"],
      lines_deleted: dev["lines_deleted"],
      avg_review_time_hours: dev["avg_review_time_hours"],
      avg_cycle_time_hours: dev["avg_cycle_time_hours"],
      dxi_score: dev["dxi_score"],
      dimension_scores: serialize_dimension_scores(dev["dimension_scores"])
    }
  end

  def serialize_dimension_scores(scores)
    return nil unless scores
    {
      review_speed: scores["review_turnaround"] || scores[:review_turnaround],
      cycle_time: scores["cycle_time"] || scores[:cycle_time],
      pr_size: scores["pr_size"] || scores[:pr_size],
      review_coverage: scores["review_coverage"] || scores[:review_coverage],
      commit_frequency: scores["commit_frequency"] || scores[:commit_frequency]
    }
  end
end
```

### cors.rb

```ruby
# config/initializers/cors.rb
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("CORS_ORIGINS", "http://localhost:3000").split(",")

    resource "/api/*",
      headers: :any,
      methods: [:get, :post, :options, :head],
      max_age: 86400
  end
end
```

### Request Spec Example

```ruby
# spec/requests/api/sprints_spec.rb
require "rails_helper"

RSpec.describe "Api::Sprints", type: :request do
  describe "GET /api/sprints/:start/:end/metrics" do
    let(:sprint) { create(:sprint, :with_developers) }

    it "returns metrics matching FastAPI contract" do
      get "/api/sprints/#{sprint.start_date}/#{sprint.end_date}/metrics"

      expect(response).to have_http_status(:ok)

      json = response.parsed_body

      # Contract assertions
      expect(json).to have_key("developers")
      expect(json).to have_key("daily")  # Not 'daily_activity'
      expect(json).to have_key("summary")
      expect(json).to have_key("team_dimension_scores")

      # Developer structure
      dev = json["developers"].first
      expect(dev).to have_key("developer")
      expect(dev).to have_key("dimension_scores")
      expect(dev["dimension_scores"]).to have_key("review_speed")  # Not 'review_turnaround'
    end
  end
end
```

---

## Dependencies & Prerequisites

### Gem Dependencies

```ruby
# Gemfile additions
gem "rack-cors"  # CORS support for API
```

### Environment Variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `CORS_ORIGINS` | Allowed frontend origins | `http://localhost:3000` |
| `GITHUB_ORG` | GitHub organization (existing) | Required |

### Prerequisites

- [ ] Rails 8 app is running and stable
- [ ] Existing Sprint model and GithubService work correctly
- [ ] Frontend can be pointed to different API URLs via env var

---

## Risk Analysis & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| API contract mismatch breaks frontend | High | High | Comprehensive request specs comparing to FastAPI |
| CORS misconfiguration blocks requests | Medium | High | Test CORS in browser early, not just curl |
| Date parsing differences | Medium | Medium | Use explicit ISO format, add validation |
| Performance regression | Low | Medium | Add caching headers, benchmark endpoints |

---

## Success Metrics

1. **Zero frontend changes** - Same TypeScript types, same API calls
2. **All tests pass** - Frontend integration tests against Rails backend
3. **Response parity** - JSON responses match FastAPI byte-for-byte (after sorting)
4. **Performance maintained** - p95 response time under 200ms for cached data

---

## Future Considerations

1. **Admin UI** - Keep Rails views for a future admin interface (different from public dashboard)
2. **API versioning** - Add `/api/v1` prefix when breaking changes are needed
3. **Authentication** - Add token auth when multi-tenant support is needed
4. **OpenAPI spec** - Generate from Rails for documentation and client generation

---

## References

### Internal References
- Existing FastAPI endpoints: `api/routers/sprints.py`, `api/routers/developers.py`
- Pydantic schemas (source of truth): `api/models/schemas.py`
- TypeScript types: `frontend/src/types/metrics.ts`
- Rails Sprint model: `opendxi_rails/app/models/sprint.rb`
- Rails DxiCalculator: `opendxi_rails/app/services/dxi_calculator.rb`

### External References
- [Rails API-only Applications](https://guides.rubyonrails.org/api_app.html)
- [rack-cors gem](https://github.com/cyu/rack-cors)
- [TanStack Query docs](https://tanstack.com/query/latest)

### Related Work
- Original migration plan: `plans/feat-rails-8-monolith-migration.md`
- Current branch: `feat/rails-8-monolith-migration`
