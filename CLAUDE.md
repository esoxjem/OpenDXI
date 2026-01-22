# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OpenDXI (Developer Experience Index) Dashboard - a full-stack application that calculates and visualizes developer productivity metrics from GitHub data. Uses Rails 8 backend (JSON API) + Next.js/React frontend with shadcn/ui components.

## Commands

### Backend (Rails 8)
```bash
cd api
bundle install
bin/rails server           # Development server on localhost:3000
bin/rails test             # Run tests
bin/rails console          # Rails console
```

### Frontend (Next.js)
```bash
cd frontend
npm install
npm run dev        # Development server on localhost:3001
npm run build      # Production build
npm run lint       # ESLint
```

Note: Configure `NEXT_PUBLIC_API_URL=http://localhost:3000` for frontend to connect to Rails.

### Prerequisites
- Ruby 3.3+
- Node.js 18+
- GitHub CLI (`gh`) authenticated with your GitHub org access

## Architecture

### Data Flow
```
GitHub GraphQL API (via `gh` CLI)
    ↓
GithubService → fetch via subprocess
    ↓
process_graphql_response() → aggregate by developer/date
    ↓
DxiCalculator → calculate DXI scores
    ↓
Sprint model → SQLite via ActiveRecord
    ↓
Serializers → JSON response
    ↓
TanStack Query hooks → React components
```

### Backend Structure (`api/`)
- `app/controllers/api/` - JSON API controllers (BaseController, SprintsController, etc.)
- `app/models/sprint.rb` - Sprint model with data storage and retrieval
- `app/services/github_service.rb` - GraphQL queries via `gh api graphql`
- `app/services/dxi_calculator.rb` - DXI score calculation algorithm
- `app/serializers/` - JSON response serializers (MetricsResponseSerializer, etc.)
- `config/routes.rb` - API routes under `/api` namespace
- `config/initializers/opendxi.rb` - Application configuration from env vars

### Frontend Structure (`frontend/src/`)
- `app/page.tsx` - Main dashboard page
- `hooks/useMetrics.ts` - TanStack Query hooks for data fetching
- `lib/api.ts` - Centralized API client
- `types/metrics.ts` - TypeScript interfaces (mirror Rails serializers)
- `components/dashboard/` - Domain components (KpiCard, Leaderboard, Charts)
- `components/ui/` - shadcn/ui components

### Key Patterns
- Backend uses subprocess to call `gh api graphql` (leverages local GitHub auth)
- Frontend uses TanStack Query for API response caching
- Types are kept in sync: Rails serializers ↔ `types/metrics.ts`
- Configuration via dotenv-rails loading `api/.env` file

## DXI Score Algorithm

Five weighted dimensions normalized to 0-100:
- Review Turnaround (25%): <2h = 100, >24h = 0
- PR Cycle Time (25%): <8h = 100, >72h = 0
- PR Size (20%): <200 lines = 100, >1000 lines = 0
- Review Coverage (15%): 10+ reviews/sprint = 100
- Commit Frequency (15%): 20+ commits/sprint = 100

Score ranges: 70+ good, 50-70 moderate, <50 needs improvement

## API Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /api/health` | Health check with version |
| `GET /api/config` | GitHub org configuration |
| `GET /api/sprints` | List available sprints |
| `GET /api/sprints/{start}/{end}/metrics?force_refresh=true` | Sprint metrics |
| `GET /api/sprints/history?count=6` | Sprint history for trends |
| `GET /api/developers/{name}/history?count=6` | Developer history |

## Caching Strategy

- **Backend**: Data is fetched from GitHub once and cached indefinitely in SQLite
- **Manual refresh**: Use `force_refresh=true` query param to pull fresh data
- **Frontend**: TanStack Query caches API responses

## Environment Variables

### Backend (`api/.env`)

Copy `api/.env.example` to `api/.env` and configure:

| Variable | Description | Default |
|----------|-------------|---------|
| `GITHUB_ORG` | GitHub organization name (required) | - |
| `SPRINT_START_DATE` | First sprint start date (YYYY-MM-DD) | `2026-01-07` |
| `SPRINT_DURATION_DAYS` | Sprint length in days | `14` |
| `MAX_PAGES_PER_QUERY` | GraphQL pagination limit | `10` |
| `CORS_ORIGINS` | Allowed CORS origins (comma-separated) | `http://localhost:3000` |

### Frontend (`frontend/.env.local`)

| Variable | Description | Default |
|----------|-------------|---------|
| `NEXT_PUBLIC_API_URL` | Backend API URL | `http://localhost:3000` |

Copy `frontend/.env.example` to `frontend/.env.local` to configure.

## Deprecated

The `deprecated_api/` directory contains the original FastAPI backend, kept for reference. The Rails backend in `api/` is now the active backend.
