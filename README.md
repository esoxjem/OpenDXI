# OpenDXI Dashboard

An open-source Developer Experience Index dashboard for measuring and improving engineering team productivity.

## Quick Start

```bash
# Install dependencies
cd api && bundle install
cd ../frontend && npm install

# Run both servers (frontend :3001, backend :3000)
bin/dev
```

Dashboard available at http://localhost:3001

## Prerequisites

- Ruby 3.3+
- Node.js 18+
- GitHub CLI (`gh`) authenticated with access to your GitHub org

## Running Individually

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

## Environment Configuration

### Backend

Copy the example environment file and configure your GitHub organization:

```bash
cp api/.env.example api/.env
```

Edit `api/.env` and set your GitHub org:

```
GITHUB_ORG=your-github-org
```

| Variable | Description | Default |
|----------|-------------|---------|
| `GITHUB_ORG` | GitHub organization name (required) | - |
| `SPRINT_START_DATE` | First sprint start date (YYYY-MM-DD) | `2026-01-07` |
| `SPRINT_DURATION_DAYS` | Sprint length in days | `14` |
| `MAX_PAGES_PER_QUERY` | GraphQL pagination limit | `10` |
| `CORS_ORIGINS` | Allowed CORS origins (comma-separated) | `http://localhost:3000` |

### Frontend

```bash
cp frontend/.env.example frontend/.env.local
```

| Variable | Description | Default |
|----------|-------------|---------|
| `NEXT_PUBLIC_API_URL` | Backend API URL | `http://localhost:3000` |

## Architecture

```
GitHub GraphQL API (via `gh` CLI)
    ↓
GithubService → fetch via subprocess
    ↓
DxiCalculator → calculate DXI scores
    ↓
Sprint model → SQLite via ActiveRecord
    ↓
Serializers → JSON response
    ↓
TanStack Query hooks → React components
```

## DXI Score Algorithm

Five weighted dimensions normalized to 0-100:

| Dimension | Weight | Optimal | Poor |
|-----------|--------|---------|------|
| Review Turnaround | 25% | <2h = 100 | >24h = 0 |
| PR Cycle Time | 25% | <8h = 100 | >72h = 0 |
| PR Size | 20% | <200 lines = 100 | >1000 lines = 0 |
| Review Coverage | 15% | 10+ reviews/sprint = 100 | 0 |
| Commit Frequency | 15% | 20+ commits/sprint = 100 | 0 |

**Score ranges:** 70+ good, 50-70 moderate, <50 needs improvement

## API Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /api/health` | Health check with version |
| `GET /api/config` | GitHub org configuration |
| `GET /api/sprints` | List available sprints |
| `GET /api/sprints/{start}/{end}/metrics?force_refresh=true` | Sprint metrics |
| `GET /api/sprints/history?count=6` | Sprint history for trends |
| `GET /api/developers/{name}/history?count=6` | Developer history |

## License

MIT
