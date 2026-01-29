# OpenDXI Dashboard

An open-source Developer Experience Index dashboard for measuring and improving engineering team productivity.

## Quick Start

```bash
# Install dependencies
cd api && bundle install

# Run the server (with Tailwind CSS watcher)
bin/dev
```

Dashboard available at http://localhost:3000

## Prerequisites

- Ruby 3.4+
- GitHub Personal Access Token with `repo` and `read:org` scopes
- GitHub OAuth App credentials (for authentication)

## Development

```bash
cd api
bundle install
bin/dev                # Development server with CSS watching
bin/rails server       # Development server only
bin/rails test         # Run tests
bin/rails console      # Rails console
```

## Environment Configuration

Copy the example environment file and configure:

```bash
cp api/.env.example api/.env
```

### Required Variables

| Variable | Description |
|----------|-------------|
| `GITHUB_ORG` | GitHub organization name |
| `GH_TOKEN` | GitHub Personal Access Token with `repo` and `read:org` scopes. [Create one](https://github.com/settings/tokens) |
| `GITHUB_CLIENT_ID` | GitHub OAuth App client ID |
| `GITHUB_CLIENT_SECRET` | GitHub OAuth App client secret |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `SPRINT_START_DATE` | First sprint start date (YYYY-MM-DD) | `2026-01-07` |
| `SPRINT_DURATION_DAYS` | Sprint length in days | `14` |
| `MAX_PAGES_PER_QUERY` | GraphQL pagination limit | `10` |
| `ALLOWED_USERS` | Comma-separated GitHub usernames allowed to access (empty = all) | - |

## Architecture

```
GitHub OAuth → SessionsController → Session
                                        ↓
GitHub GraphQL API (via GH_TOKEN)       ↓
    ↓                                   ↓
GithubService → fetch via Faraday  →   ↓
    ↓                                   ↓
DxiCalculator → calculate DXI scores    ↓
    ↓                                   ↓
Sprint model → SQLite via ActiveRecord  ↓
    ↓                                   ↓
DashboardController → Turbo Frames → Views (ERB + Tailwind)
```

### Tech Stack

- **Backend**: Rails 8.1 with Hotwire (Turbo + Stimulus)
- **Frontend**: Server-rendered ERB templates with Tailwind CSS
- **Charts**: Chartkick with ApexCharts
- **Database**: SQLite (development), configurable for production
- **Authentication**: GitHub OAuth via OmniAuth

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

The dashboard also exposes a JSON API:

| Endpoint | Description |
|----------|-------------|
| `GET /api/health` | Health check with version |
| `GET /api/config` | GitHub org configuration |
| `GET /api/sprints` | List available sprints |
| `GET /api/sprints/{start}/{end}/metrics?force_refresh=true` | Sprint metrics |
| `GET /api/sprints/history?count=6` | Sprint history for trends |
| `GET /api/developers/{name}/history?count=6` | Developer history |

## Deployment

### Docker

```bash
cd api
docker build -t opendxi .
docker run -d -p 80:80 \
  -e RAILS_MASTER_KEY=<value from config/master.key> \
  -e GITHUB_ORG=your-org \
  -e GH_TOKEN=your-token \
  -e GITHUB_CLIENT_ID=your-client-id \
  -e GITHUB_CLIENT_SECRET=your-secret \
  --name opendxi opendxi
```

### Kamal

The app is configured for deployment with Kamal. See `config/deploy.yml`.

## License

MIT
