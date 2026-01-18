# OpenDXI Dashboard

An open-source Developer Experience Index dashboard for measuring and improving engineering team productivity.

## Running the Application

### Prerequisites

- Python 3.11+
- Node.js 18+
- GitHub CLI (`gh`) authenticated with access to your GitHub org

### Backend (FastAPI)

```bash
cd api
pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```

API available at http://localhost:8000

### Frontend (Next.js)

```bash
cd frontend
npm install
npm run dev
```

Dashboard available at http://localhost:3000

## Environment Configuration

### Backend

Copy the example environment file and configure your GitHub organization:

```bash
cp .env.example .env
```

Edit `.env` and set your GitHub org:

```
GITHUB_ORG=your-github-org
```

All available options:

| Variable | Description | Default |
|----------|-------------|---------|
| `GITHUB_ORG` | GitHub organization name (required) | - |
| `SPRINT_START_DATE` | First sprint start date (YYYY-MM-DD) | `2026-01-07` |
| `SPRINT_DURATION_DAYS` | Sprint length in days | `14` |
| `DB_PATH` | SQLite database file path | `.data/opendxi.db` |
| `DB_TIMEOUT` | Database connection timeout (seconds) | `30` |
| `MAX_PAGES_PER_QUERY` | GraphQL pagination limit | `10` |
| `HOST` | Server bind address | `0.0.0.0` |
| `PORT` | Server port | `8000` |
| `DEBUG` | Enable debug mode | `True` |
| `CORS_ORIGINS` | Allowed CORS origins (JSON array) | `["http://localhost:3000"]` |

### Frontend

```bash
cp frontend/.env.example frontend/.env.local
```

| Variable | Description | Default |
|----------|-------------|---------|
| `NEXT_PUBLIC_API_URL` | Backend API URL | `http://localhost:8000` |
