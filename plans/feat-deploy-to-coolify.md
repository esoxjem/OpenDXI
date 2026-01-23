# Deploy OpenDXI to Coolify

## Overview

Deploy the OpenDXI application (Rails 8 API + Next.js frontend) to Coolify with:
- **Frontend**: https://dxi.esoxjem.com
- **API**: https://dxi-api.esoxjem.com

## Problem Statement

OpenDXI needs a production deployment. The app consists of:
1. **Rails 8 API** - Serves JSON metrics from GitHub data, uses SQLite for caching
2. **Next.js Frontend** - React dashboard with shadcn/ui components

Current state:
- ✅ Rails Dockerfile exists (but missing `gh` CLI)
- ❌ Frontend Dockerfile missing
- ❌ `next.config.ts` missing `output: 'standalone'`
- ❌ No production environment configuration

## Proposed Solution

Deploy as **two separate Coolify resources** from the same GitHub repository:
- Independent deployment cycles via watch paths
- Simpler than Docker Compose for this use case
- Each service gets its own domain

## Technical Approach

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Coolify                               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────┐        ┌──────────────────┐          │
│  │  Next.js Frontend │        │   Rails API      │          │
│  │  dxi.esoxjem.com  │───────▶│  dxi-api.esoxjem │          │
│  │  Port: 3000       │        │  Port: 80        │          │
│  │  Watch: frontend/**│        │  Watch: api/**   │          │
│  └──────────────────┘        └────────┬─────────┘          │
│                                        │                     │
│                              ┌─────────▼─────────┐          │
│                              │  SQLite Volume    │          │
│                              │  /rails/storage   │          │
│                              └───────────────────┘          │
│                                        │                     │
└────────────────────────────────────────┼─────────────────────┘
                                         │
                              ┌──────────▼──────────┐
                              │    GitHub GraphQL   │
                              │  (Direct HTTP with  │
                              │   GH_TOKEN via      │
                              │   Faraday)          │
                              └─────────────────────┘
```

### Implementation Phases

#### Phase 1: Migrate GithubService to Direct HTTP

The current `GithubService` shells out to the `gh` CLI binary, which would require installing it in the Docker image (+50MB). Instead, we'll refactor to use direct HTTP calls with Faraday.

> **📄 See detailed plan:** [refactor-github-service-to-http.md](./refactor-github-service-to-http.md)

**Summary of changes:**
- Add `faraday` and `faraday-retry` gems
- Replace `Open3.capture3("gh", ...)` with `Faraday.post`
- Replace `validate_gh_cli!` with `validate_github_token!`
- Add proper HTTP error handling and retry logic
- Add WebMock tests for API interactions

**Benefits:**
- No gh CLI binary needed in Docker image (saves ~50MB)
- Cleaner error handling with HTTP status codes
- Automatic retry with exponential backoff
- Better testability (WebMock)

#### Phase 2: Prepare Docker Configuration

**2.1 Create Frontend Dockerfile**

```dockerfile
# frontend/Dockerfile
FROM node:22-alpine AS base

# Stage 1: Install dependencies
FROM base AS deps
RUN apk add --no-cache libc6-compat
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci

# Stage 2: Build application
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Build-time environment variable
ARG NEXT_PUBLIC_API_URL
ENV NEXT_PUBLIC_API_URL=${NEXT_PUBLIC_API_URL}
ENV NEXT_TELEMETRY_DISABLED=1

RUN npm run build

# Stage 3: Production runner
FROM base AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

# Create non-root user
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

# Copy standalone build output
COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs

EXPOSE 3000
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

CMD ["node", "server.js"]
```

**1.3 Update next.config.ts for Standalone Output**

```typescript
// frontend/next.config.ts
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "standalone",
};

export default nextConfig;
```

**1.4 Add Frontend .dockerignore**

```
# frontend/.dockerignore
node_modules
.next
.git
*.md
.env*.local
```

#### Phase 3: Configure Rails for Production

**3.1 Update Rails Allowed Hosts**

```ruby
# api/config/environments/production.rb - Uncomment and update line 63-66
config.hosts << "dxi-api.esoxjem.com"
config.hosts << "localhost"  # For health checks
```

**3.2 Create Production Environment File Template**

```bash
# api/.env.production.example
RAILS_ENV=production
RAILS_MASTER_KEY=<from config/master.key>

# GitHub Configuration (required)
GITHUB_ORG=your-org-name
GH_TOKEN=ghp_your_personal_access_token

# CORS - must include frontend URL
CORS_ORIGINS=https://dxi.esoxjem.com

# Optional - Sprint Configuration
SPRINT_START_DATE=2026-01-07
SPRINT_DURATION_DAYS=14
MAX_PAGES_PER_QUERY=10
```

#### Phase 4: Deploy to Coolify

**4.1 Create GitHub Personal Access Token**

Required scopes for the token:
- `repo` - Full control of private repositories
- `read:org` - Read organization membership

Generate at: https://github.com/settings/tokens/new

**4.2 Configure DNS Records**

Add A records pointing to your Coolify server IP:
```
dxi.esoxjem.com      A    <coolify-server-ip>
dxi-api.esoxjem.com  A    <coolify-server-ip>
```

**4.3 Create Coolify Project**

```bash
# Using Coolify CLI (already authenticated)
# Create project in Coolify UI: Projects > New > "OpenDXI"
# Add environment: "Production"
```

**4.4 Add Rails API Resource**

In Coolify UI:
1. Add New Resource → Public Repository (or Private with deploy key)
2. Repository: `https://github.com/your-username/opendxi`
3. Branch: `main`
4. Build Pack: **Dockerfile**
5. Base Directory: `/api`
6. Dockerfile Location: `/api/Dockerfile`
7. Watch Paths: `api/**`

Domain Configuration:
- Domain: `https://dxi-api.esoxjem.com`

Storage Configuration:
- Add Volume: `opendxi-rails-storage` → `/rails/storage`

Environment Variables:
```
RAILS_MASTER_KEY=<value>
GITHUB_ORG=<your-org>
GH_TOKEN=<token>
CORS_ORIGINS=https://dxi.esoxjem.com
SPRINT_START_DATE=2026-01-07
SPRINT_DURATION_DAYS=14
```

Health Check:
- Path: `/up`
- Interval: 30s

**4.5 Add Next.js Frontend Resource**

In Coolify UI:
1. Add New Resource → Same Repository
2. Branch: `main`
3. Build Pack: **Dockerfile**
4. Base Directory: `/frontend`
5. Dockerfile Location: `/frontend/Dockerfile`
6. Watch Paths: `frontend/**`

Domain Configuration:
- Domain: `https://dxi.esoxjem.com`

Build Arguments:
```
NEXT_PUBLIC_API_URL=https://dxi-api.esoxjem.com
```

Health Check:
- Path: `/`
- Interval: 30s

**4.6 Deploy Both Services**

```bash
# Via Coolify CLI
coolify deploy name opendxi-api
coolify deploy name opendxi-frontend

# Or trigger via UI: Deploy button on each resource
```

#### Phase 5: Verification

**5.1 Verify API Health**

```bash
curl https://dxi-api.esoxjem.com/api/health
# Expected: {"status":"ok","version":"..."}
```

**5.2 Verify Frontend Loads**

```bash
curl -I https://dxi.esoxjem.com
# Expected: HTTP/2 200
```

**5.3 Verify GitHub Integration**

```bash
curl https://dxi-api.esoxjem.com/api/config
# Expected: {"github_org":"your-org",...}
```

**5.4 Test Full Data Flow**

1. Open https://dxi.esoxjem.com in browser
2. Select a sprint date range
3. Verify metrics load from GitHub

## Acceptance Criteria

### Functional Requirements

- [ ] Frontend accessible at https://dxi.esoxjem.com
- [ ] API accessible at https://dxi-api.esoxjem.com
- [ ] Dashboard displays sprint metrics from GitHub
- [ ] Force refresh triggers new GitHub data fetch
- [ ] Data persists across container restarts (SQLite volume)

### Non-Functional Requirements

- [ ] SSL certificates auto-provisioned via Let's Encrypt
- [ ] Health checks pass for both services
- [ ] Independent deployments via watch paths work
- [ ] Container restarts preserve database data

### Quality Gates

- [ ] Both Dockerfiles build successfully
- [ ] No CORS errors in browser console
- [ ] API responds in < 500ms for cached data
- [ ] GitHub API errors are logged, not exposed to frontend

## Environment Variables Reference

### Rails API

| Variable | Required | Description |
|----------|----------|-------------|
| `RAILS_MASTER_KEY` | ✅ | Decrypts credentials.yml.enc |
| `GITHUB_ORG` | ✅ | GitHub organization to fetch metrics |
| `GH_TOKEN` | ✅ | GitHub PAT with repo, read:org scopes |
| `CORS_ORIGINS` | ✅ | Frontend URL(s), comma-separated |
| `SPRINT_START_DATE` | ❌ | First sprint start date (default: 2026-01-07) |
| `SPRINT_DURATION_DAYS` | ❌ | Sprint length (default: 14) |
| `MAX_PAGES_PER_QUERY` | ❌ | GraphQL pagination limit (default: 10) |

### Next.js Frontend

| Variable | Required | Build/Runtime | Description |
|----------|----------|---------------|-------------|
| `NEXT_PUBLIC_API_URL` | ✅ | Build | Rails API URL |

## Risk Analysis & Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| SQLite volume not persisted | Data loss | Verify volume mount before deploying |
| GitHub rate limiting | Service degradation | Cache aggressively, use `force_refresh` sparingly |
| gh CLI not found in container | API failures | Test Docker build locally first |
| CORS misconfiguration | Frontend broken | Include exact production URL in CORS_ORIGINS |
| Watch paths trigger wrong deploys | Unnecessary rebuilds | Test with small commits to each directory |

## Rollback Procedure

1. In Coolify UI, select the resource
2. Go to Deployments tab
3. Click "Rollback" on previous successful deployment
4. **Note**: Database migrations are NOT rolled back automatically

For database issues:
```bash
# SSH to server or use Coolify terminal
# Backup current database
cp /rails/storage/production.sqlite3 /rails/storage/production.sqlite3.backup

# Restore from backup if needed
cp /rails/storage/production.sqlite3.backup /rails/storage/production.sqlite3
```

## Files to Create/Modify

| File | Action | Purpose |
|------|--------|---------|
| `api/Gemfile` | Modify | Add faraday, faraday-retry, webmock gems |
| `api/app/services/github_service.rb` | Modify | Replace gh CLI with direct HTTP calls |
| `api/test/support/github_api_stub.rb` | Create | Test helpers for stubbing GitHub API |
| `api/test/services/github_service_test.rb` | Create | Unit tests for HTTP implementation |
| `frontend/Dockerfile` | Create | Production Next.js container |
| `frontend/next.config.ts` | Modify | Add standalone output |
| `frontend/.dockerignore` | Create | Optimize Docker build context |
| `api/config/environments/production.rb` | Modify | Add allowed hosts |

## References

### Internal References
- GithubService implementation: `api/app/services/github_service.rb:8-9` (recommends Faraday migration)
- GraphQL queries: `api/app/services/github_service.rb:21-85` (REPOS_QUERY, PRS_QUERY, COMMITS_QUERY)
- Database configuration: `api/config/database.yml` (SQLite paths)
- CORS configuration: `api/config/initializers/cors.rb`
- Existing Dockerfile: `api/Dockerfile`

### External References
- [Coolify Documentation](https://coolify.io/docs/)
- [Coolify CLI GitHub](https://github.com/coollabsio/coolify-cli)
- [Next.js Standalone Output](https://nextjs.org/docs/app/api-reference/next-config-js/output)
- [GitHub CLI Installation](https://github.com/cli/cli/blob/trunk/docs/install_linux.md)
- [Rails 8 Docker Best Practices](https://guides.rubyonrails.org/v8.0/getting_started)
