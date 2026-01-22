# Dual Frontend Architecture - RESOLVED

---
status: completed
priority: p3
issue_id: "016"
tags: [code-review, architecture, resolved]
dependencies: []
---

## Problem Statement

The project maintained two complete frontends: React/Next.js (`frontend/`) and Rails Hotwire (`api/app/views/`). This created maintenance burden and architectural confusion.

**Why it mattered**: Double the frontend code to maintain. Serializers existed solely to match "FastAPI contract". Risk of feature drift between frontends.

## Resolution

**Decision**: Option C - Remove Hotwire Views. Keep React frontend, Rails becomes pure JSON API.

### Changes Made

1. **Removed Gemfile dependencies**:
   - `turbo-rails` (Hotwire Turbo)
   - `stimulus-rails` (Hotwire Stimulus)
   - `tailwindcss-rails` (Tailwind CSS)
   - `chartkick` (Chart library)
   - `propshaft` (Asset pipeline)
   - `importmap-rails` (JS import maps)
   - `web-console` (Development HTML console)
   - `capybara`, `selenium-webdriver` (System testing)

2. **Removed directories**:
   - `api/app/views/` (All view templates)
   - `api/app/javascript/` (Stimulus controllers, Turbo imports)
   - `api/app/assets/` (Tailwind CSS, images, stylesheets)

3. **Removed controllers**:
   - `dashboard_controller.rb` (HTML dashboard)
   - `developers_controller.rb` (HTML developer pages)
   - `sprints_controller.rb` (HTML sprint views)

4. **Updated routes** (`config/routes.rb`):
   - Removed root route, dashboard routes, HTML developer/sprint routes
   - Kept only API namespace routes

5. **Updated configuration**:
   - `config/application.rb`: Set `config.api_only = true`, removed action_view/action_cable
   - `config/initializers/content_security_policy.rb`: Simplified for API-only
   - `config/environments/development.rb`: Removed asset/view config
   - Removed `config/importmap.rb`
   - Removed `config/initializers/assets.rb`
   - Removed `bin/importmap`

6. **Updated ApplicationController**: Simplified for API-only mode

7. **Removed tests**: `test/controllers/dashboard_controller_test.rb`

### Verification

- All 73 remaining tests pass
- Bundle install successful (14 dependencies, 102 gems)
- Rails app boots in API-only mode

## Technical Details

**Final Architecture**:
- `api/` - Rails 8 JSON API (ActionController::API)
- `frontend/` - Next.js React frontend with shadcn/ui
- Clear separation: Rails handles data/business logic, React handles UI

**Gem count reduction**: From ~130 gems to 102 gems (simplified dependency tree)

## Acceptance Criteria

- [x] Hotwire views removed
- [x] View-related gems removed
- [x] HTML routes removed
- [x] Tests pass
- [x] Rails configured for API-only mode

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-22 | Identified by dhh-rails-reviewer agent | Dual frontend maintenance burden |
| 2026-01-22 | Implemented Option C: Removed Hotwire views | Rails API-only mode is clean, reduces dependencies |

## Resources

- PR #2: https://github.com/esoxjem/OpenDXI/pull/2
- Rails API-only: https://guides.rubyonrails.org/api_app.html
