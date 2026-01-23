# Deploy OpenDXI to Coolify

## Enhancement Summary

**Deepened on:** 2026-01-23
**Research agents used:** 8 reviewers + 1 researcher + Context7 documentation
**Sections enhanced:** All phases + new sections added

### Key Improvements
1. Added comprehensive security recommendations (host auth, OAuth vars, session cookies)
2. Added deployment ordering requirements (API must deploy first)
3. Added performance optimizations (health check timing, transaction scope)
4. Added detailed verification checklist with rollback procedures
5. Identified and documented architectural constraints and trade-offs

### Critical Issues Discovered
- Missing OAuth environment variables in deployment plan
- Health endpoint `/api/health` requires authentication (use `/up` for Coolify)
- SQLite transaction scope in SprintLoader causes blocking during force_refresh
- CORS max_age change is unnecessary (removed from plan)

---

## Overview

Deploy the OpenDXI application (Rails 8 API + Next.js frontend) to Coolify with:
- **Frontend**: https://dxi.esoxjem.com
- **API**: https://dxi-api.esoxjem.com

## Problem Statement

OpenDXI needs a production deployment. The app consists of:
1. **Rails 8 API** - Serves JSON metrics from GitHub data, uses SQLite for caching
2. **Next.js Frontend** - React dashboard with shadcn/ui components

Current state:
- ✅ Rails Dockerfile exists
- ✅ GithubService uses direct HTTP via Faraday (no `gh` CLI needed)
- ❌ Frontend Dockerfile missing
- ❌ `next.config.ts` missing `output: 'standalone'`
- ❌ No production environment configuration

## Proposed Solution

Deploy as **two separate Coolify resources** from the same GitHub repository:
- Independent deployment cycles via watch paths
- Simpler than Docker Compose for this use case
- Each service gets its own domain

### Research Insights: Why Two Services vs Docker Compose

**Best Practices (from Coolify documentation):**
- Docker Compose deployments do NOT support rolling updates in Coolify
- Environment variables must be in compose file, not Coolify UI for Compose
- Static container names in Compose prevent proper instance management

**Recommendation:** Individual Dockerfile deployments (as in this plan) provide maximum Coolify feature compatibility.

## Technical Approach

### Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Coolify Server                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────────────────┐        ┌───────────────────────────┐         │
│  │    Next.js Frontend      │        │      Rails 8 API          │         │
│  │    dxi.esoxjem.com       │        │    dxi-api.esoxjem.com    │         │
│  ├──────────────────────────┤        ├───────────────────────────┤         │
│  │ Port: 3000               │  HTTP  │ Port: 80 (Thruster)       │         │
│  │ Scale: N instances       │───────▶│ Scale: 1 instance MAX     │         │
│  │ Stateless                │  +     │ Stateful (SQLite)         │         │
│  │                          │ Cookie │                           │         │
│  │ TanStack Query Cache     │        │ SprintLoader + Cache      │         │
│  └──────────────────────────┘        └─────────────┬─────────────┘         │
│           │                                         │                       │
│           │                           ┌─────────────▼──────────────┐        │
│           │                           │   SQLite Volume            │        │
│           │                           │   /rails/storage           │        │
│           │                           │   production.sqlite3       │        │
│           │                           │   [SPOF - Single Instance] │        │
│           │                           └────────────────────────────┘        │
│           │                                         │                       │
└───────────┼─────────────────────────────────────────┼───────────────────────┘
            │                                         │
   ┌────────▼────────┐                    ┌───────────▼───────────┐
   │    Browsers     │                    │   GitHub GraphQL API  │
   │  (End Users)    │                    │   (External Service)  │
   └─────────────────┘                    └───────────────────────┘
```

### Architectural Constraints (Research Findings)

| Constraint | Impact | Mitigation |
|------------|--------|------------|
| SQLite single-instance | No horizontal scaling | Accept for dashboard workload; document PostgreSQL migration path |
| Build-time `NEXT_PUBLIC_*` | Image is environment-specific | Document that each environment needs its own build |
| Cross-origin cookies | May be affected by browser privacy changes | Monitor; have API proxy migration plan |

### Implementation Phases

#### Phase 1: Prepare Docker Configuration

**1.1 Create Frontend Dockerfile**

```dockerfile
# frontend/Dockerfile
FROM node:22-alpine AS base

# Stage 1: Install dependencies
FROM base AS deps
RUN apk add --no-cache libc6-compat
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci && npm cache clean --force

# Stage 2: Build application
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# NEXT_PUBLIC_* variables are inlined at build time.
# Each environment (staging, production) requires its own image build.
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

# Note: Removed Docker HEALTHCHECK - Coolify handles health checking via UI config
# Using longer start-period (30s) allows for Next.js cold start

CMD ["node", "server.js"]
```

### Research Insights: Dockerfile Optimizations

**Best Practices Applied:**
- Multi-stage build reduces final image size (only standalone output)
- `npm cache clean --force` reduces deps layer size
- Non-root user (nextjs:1001) for security
- Removed Docker HEALTHCHECK (Coolify provides this, avoids duplication)

**Why no HEALTHCHECK in Dockerfile:**
- Coolify provides its own health checking mechanism configured in the UI
- Docker's HEALTHCHECK duplicates this functionality
- Coolify's health check is more configurable (path, interval, etc.)

---

**1.2 Update next.config.ts for Standalone Output**

```typescript
// frontend/next.config.ts
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "standalone",
  poweredByHeader: false, // Security: Remove X-Powered-By header

  // Security headers
  async headers() {
    return [
      {
        source: "/:path*",
        headers: [
          { key: "X-Frame-Options", value: "DENY" },
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
        ],
      },
    ];
  },
};

export default nextConfig;
```

### Research Insights: Next.js Standalone Mode

**From Next.js Documentation (Context7):**
- `output: "standalone"` creates a `.next/standalone` folder with only necessary files
- Minimal `server.js` is output which can run without `next start`
- Public and static folders must be manually copied (Dockerfile handles this)
- Reduces deployment size drastically vs. full node_modules

**Security Headers Added:**
- `X-Frame-Options: DENY` - Prevents clickjacking
- `X-Content-Type-Options: nosniff` - Prevents MIME sniffing
- `Referrer-Policy: strict-origin-when-cross-origin` - Controls referrer leakage

---

**1.3 Add Frontend .dockerignore**

```
# frontend/.dockerignore
node_modules
.next
.git
.gitignore
*.md
.env*
.DS_Store
coverage
.turbo
```

**1.4 Create Frontend Health Check Endpoint**

Create a dedicated health endpoint that doesn't require authentication:

```typescript
// frontend/src/app/api/health/route.ts
export async function GET() {
  return Response.json({
    status: 'ok',
    timestamp: new Date().toISOString()
  });
}
```

**Why:** The root route `/` may have authentication or redirects. A dedicated `/api/health` endpoint ensures reliable health checks.

---

#### Phase 2: Configure Rails for Production

**2.1 Update Rails Allowed Hosts**

```ruby
# api/config/environments/production.rb - Uncomment and update
config.hosts << "dxi-api.esoxjem.com"

# Exclude /up endpoint from host verification (for Coolify health checks)
config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
```

### Research Insights: Rails 8 Host Configuration

**From Rails 8 Guides (Context7):**
- `config.hosts` prevents DNS rebinding attacks
- The `exclude` option allows health checks without valid Host header
- Pattern `/up` is Rails 8's default health check endpoint (from `rails/health#show`)

**Security Note:** Without host authorization, the app is vulnerable to:
- DNS rebinding attacks
- Host header injection
- Cache poisoning via manipulated Host headers

---

**2.2 Add GH_TOKEN Validation (Improved)**

Create an initializer that warns but allows boot:

```ruby
# api/config/initializers/github.rb
Rails.application.config.after_initialize do
  if Rails.env.production? && ENV["GH_TOKEN"].blank?
    Rails.logger.error("FATAL: GH_TOKEN environment variable must be set in production")
    # Note: App boots, health check works, but API calls will fail gracefully
  end
end
```

### Research Insights: Fail-Fast vs. Fail-Graceful

**Why not raise at boot:**
- Raising in an initializer prevents `rails console` for debugging
- Prevents `rails db:migrate` if token is missing
- Health checks fail, causing deployment loops

**Improved pattern:** Warn at boot, fail at point of use in GithubService.

---

**2.3 Simplify database.yml**

The default Rails 8 `database.yml` configures 4 SQLite databases (primary, cache, queue, cable). Since this app uses `:memory_store` for cache and `:inline` for jobs, simplify to only the primary database:

```yaml
# api/config/database.yml - production section
production:
  <<: *default
  database: storage/production.sqlite3
```

### Research Insights: Database Configuration

**Why simplify:**
- Only `primary` database is used
- Cache uses `:memory_store` (configured in production.rb)
- Jobs use `:inline` (no Solid Queue)
- Extra database files created on boot waste disk space

---

**2.4 ~~Reduce CORS max_age for Debugging~~ (REMOVED)**

### Research Insights: CORS max_age

**Why removed from plan:**
- CORS preflight caching has no debugging benefit
- If CORS is misconfigured, errors appear immediately in browser console
- The 24-hour default (`max_age: 86400`) is production-appropriate
- This change added unnecessary complexity with no benefit

**Keep the existing `max_age: 86400`.**

---

#### Phase 3: Deploy to Coolify

**⚠️ CRITICAL: Deployment Order**

```
┌─────────────────────────────────────────────────────────────┐
│  DEPLOYMENT ORDER (REQUIRED FOR INITIAL DEPLOYMENT)         │
├─────────────────────────────────────────────────────────────┤
│  1. Deploy Rails API first                                   │
│  2. Verify: curl https://dxi-api.esoxjem.com/up returns 200 │
│  3. Then deploy Next.js frontend                            │
│     (needs API URL for build-time environment variable)     │
└─────────────────────────────────────────────────────────────┘
```

**Why:** The frontend build requires `NEXT_PUBLIC_API_URL` which must resolve. If API isn't deployed first, frontend build may succeed but will show errors when users try to use it.

---

**3.1 Create GitHub Personal Access Token**

### Research Insights: Token Permissions

**Current plan requests:**
- `repo` - Full control of private repositories
- `read:org` - Read organization membership

**Security Recommendation:** Use Fine-grained Personal Access Token instead:
- Repository access: Only required repositories
- Permissions: Read-only for repository contents, pull requests, and commits

**Actual required permissions:**
- Read repository metadata
- Read pull requests
- Read commits
- Read reviews

Generate at: https://github.com/settings/tokens/new (Classic) or https://github.com/settings/personal-access-tokens/new (Fine-grained)

---

**3.2 Configure DNS Records**

Add A records pointing to your Coolify server IP:
```
dxi.esoxjem.com      A    <coolify-server-ip>
dxi-api.esoxjem.com  A    <coolify-server-ip>
```

### Research Insights: DNS and SSL

**For Let's Encrypt HTTP-01 challenge:**
- DNS A record must point to Coolify server
- Port 80 must be open and reachable
- If using Cloudflare, set to "DNS Only" (gray cloud, not orange proxy)

**Verification command:**
```bash
dig dxi.esoxjem.com +short
dig dxi-api.esoxjem.com +short
```

---

**3.3 Create Coolify Project**

In Coolify UI:
1. Projects → New → Name: "OpenDXI"
2. Add environment: "Production"

**3.4 Add Rails API Resource**

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

### Research Insights: SQLite Volume Configuration

**Critical:** Mount the DIRECTORY, not the file:
- ✅ Correct: `opendxi-rails-storage` → `/rails/storage`
- ❌ Wrong: `opendxi-rails-storage` → `/rails/storage/production.sqlite3`

**Why:** SQLite WAL mode creates `-wal` and `-shm` files alongside the database. Mounting the directory ensures all files are persisted.

---

Environment Variables (required):
```
RAILS_MASTER_KEY=<value>
GITHUB_ORG=<your-org>
GH_TOKEN=<token>
CORS_ORIGINS=https://dxi.esoxjem.com
GITHUB_OAUTH_CLIENT_ID=<oauth-app-id>
GITHUB_OAUTH_CLIENT_SECRET=<oauth-secret>
GITHUB_OAUTH_CALLBACK_URL=https://dxi-api.esoxjem.com/auth/github/callback
FRONTEND_URL=https://dxi.esoxjem.com
```

### Research Insights: Missing OAuth Variables

**Security audit discovered:** The original plan omitted OAuth secrets. Without these, authentication will fail completely.

**To create GitHub OAuth App:**
1. Go to https://github.com/settings/developers
2. New OAuth App
3. Homepage URL: `https://dxi.esoxjem.com`
4. Callback URL: `https://dxi-api.esoxjem.com/auth/github/callback`

---

Health Check:
- Path: `/up` (NOT `/api/health` - that requires authentication)
- Interval: 30s
- Start Period: 30s (allow for cold start)

Scaling (⚠️ Critical):
- **Max Instances: 1** - SQLite cannot handle concurrent writes from multiple instances

### Research Insights: Why Single Instance

**SQLite limitations:**
- No concurrent write support
- Database is local to container (volume mount)
- No read replicas possible

**For future scaling, migration path:**
1. Litestream for SQLite replication to S3 (read replicas)
2. Migration to PostgreSQL if scaling becomes necessary

---

**3.5 Add Next.js Frontend Resource**

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
- Path: `/api/health` (the new dedicated endpoint)
- Interval: 30s
- Start Period: 30s (allow for Next.js cold start)

### Research Insights: Health Check Start Period

**Why 30 seconds:**
- Next.js apps can take 10-15s to start on cold starts
- Default 5s may cause false-negative health failures
- Coolify may repeatedly restart containers if start period is too short

---

**3.6 Deploy Both Services**

1. **First:** Deploy Rails API
2. **Wait:** Verify `curl https://dxi-api.esoxjem.com/up` returns 200
3. **Then:** Deploy Next.js frontend
4. **Verify:** Both services healthy in Coolify dashboard

Coolify will automatically deploy on subsequent pushes to the watched paths.

---

#### Phase 4: Verification

**4.1 Verify API Health**

```bash
# Rails default health endpoint (used by Coolify)
curl https://dxi-api.esoxjem.com/up
# Expected: HTML with "up"

# Application health endpoint (requires auth after fix)
curl https://dxi-api.esoxjem.com/api/health
# Expected: {"status":"ok","version":"..."}
```

**4.2 Verify Frontend Loads**

```bash
curl -I https://dxi.esoxjem.com
# Expected: HTTP/2 200

# Verify security headers
curl -I https://dxi.esoxjem.com 2>&1 | grep -E "(X-Frame|X-Content|Referrer)"
# Expected: Security headers present
```

**4.3 Verify GitHub Integration**

```bash
curl https://dxi-api.esoxjem.com/api/config
# Expected: {"github_org":"your-org",...}
```

**4.4 Verify CORS**

```bash
# Preflight request
curl -X OPTIONS https://dxi-api.esoxjem.com/api/sprints \
  -H "Origin: https://dxi.esoxjem.com" \
  -H "Access-Control-Request-Method: GET" \
  -I

# Should include:
# Access-Control-Allow-Origin: https://dxi.esoxjem.com
# Access-Control-Allow-Credentials: true
```

**4.5 Verify SSL Certificates**

```bash
echo | openssl s_client -connect dxi.esoxjem.com:443 -servername dxi.esoxjem.com 2>/dev/null | openssl x509 -noout -dates
# Should show valid date range

echo | openssl s_client -connect dxi-api.esoxjem.com:443 -servername dxi-api.esoxjem.com 2>/dev/null | openssl x509 -noout -issuer
# Should show: Let's Encrypt
```

**4.6 Verify Volume Persistence**

```bash
# 1. Trigger data creation
curl "https://dxi-api.esoxjem.com/api/sprints/2026-01-07/2026-01-20/metrics"

# 2. In Coolify, restart the Rails container

# 3. Verify data persists
curl "https://dxi-api.esoxjem.com/api/sprints"
# Should show the sprint created in step 1
```

**4.7 Test Full Data Flow**

1. Open https://dxi.esoxjem.com in browser
2. Login with GitHub OAuth
3. Select a sprint date range
4. Verify metrics load from GitHub

---

## Acceptance Criteria

### Functional Requirements

- [ ] Frontend accessible at https://dxi.esoxjem.com
- [ ] API accessible at https://dxi-api.esoxjem.com
- [ ] GitHub OAuth login works
- [ ] Dashboard displays sprint metrics from GitHub
- [ ] Force refresh triggers new GitHub data fetch
- [ ] Data persists across container restarts (SQLite volume)

### Non-Functional Requirements

- [ ] SSL certificates auto-provisioned via Let's Encrypt
- [ ] Health checks pass for both services
- [ ] Independent deployments via watch paths work
- [ ] Container restarts preserve database data
- [ ] Security headers present on frontend responses

### Quality Gates

- [ ] Both Dockerfiles build successfully
- [ ] No CORS errors in browser console
- [ ] No authentication errors on protected routes

---

## Environment Variables Reference

### Rails API

| Variable | Required | Description |
|----------|----------|-------------|
| `RAILS_MASTER_KEY` | ✅ | Decrypts credentials.yml.enc |
| `GITHUB_ORG` | ✅ | GitHub organization to fetch metrics |
| `GH_TOKEN` | ✅ | GitHub PAT with repo, read:org scopes |
| `CORS_ORIGINS` | ✅ | Frontend URL(s), comma-separated |
| `GITHUB_OAUTH_CLIENT_ID` | ✅ | GitHub OAuth App client ID |
| `GITHUB_OAUTH_CLIENT_SECRET` | ✅ | GitHub OAuth App client secret |
| `GITHUB_OAUTH_CALLBACK_URL` | ✅ | OAuth callback URL |
| `FRONTEND_URL` | ✅ | Frontend URL for redirects |
| `SPRINT_START_DATE` | ❌ | First sprint start date (default: 2026-01-07) |
| `SPRINT_DURATION_DAYS` | ❌ | Sprint length (default: 14) |
| `MAX_PAGES_PER_QUERY` | ❌ | GraphQL pagination limit (default: 10) |

### Next.js Frontend

| Variable | Required | Build/Runtime | Description |
|----------|----------|---------------|-------------|
| `NEXT_PUBLIC_API_URL` | ✅ | Build | Rails API URL |

---

## Files to Create/Modify

| File | Action | Status | Purpose |
|------|--------|--------|---------|
| `frontend/Dockerfile` | Create | ✅ Done | Production Next.js container |
| `frontend/next.config.ts` | Modify | ✅ Done | Add standalone output + security headers |
| `frontend/.dockerignore` | Create | ✅ Done | Optimize Docker build context |
| `frontend/src/app/api/health/route.ts` | Create | ✅ Done | Dedicated health check endpoint |
| `api/config/environments/production.rb` | Modify | ✅ Done | Add allowed hosts + host_authorization |
| `api/config/initializers/github.rb` | Create | ✅ Done | GH_TOKEN validation (warn, don't block) |
| `api/config/database.yml` | Modify | ✅ Done | Remove unused cache/queue/cable databases |

---

## Rollback Procedures

### Code Rollback

```bash
# In Coolify, each deployment creates a new container
# Previous containers are kept for quick rollback

# Option 1: Redeploy previous commit
# In Coolify UI: Deployments → Select previous → Redeploy

# Option 2: Git revert and push
git revert HEAD
git push origin main
# Watch paths will trigger automatic redeploy
```

### Environment Variable Issues

If deployment fails due to missing environment variables:
1. Check Coolify logs for the specific error
2. Add missing variable in Coolify UI → Environment Variables
3. Trigger manual redeploy

### Volume Recovery

SQLite data is regenerable from GitHub. To recover:
1. Clear the volume or remove corrupted database
2. Restart the Rails container
3. Data will be regenerated on first API request

---

## Monitoring and Logging

### In Coolify

- **Logs:** Resources → Rails API/Next.js → Logs
- **Health Status:** Green indicator when health checks pass
- **Deployments:** History of all deployments with rollback option

### Recommended: Add Error Tracking

Consider adding Sentry for production error tracking:

**Rails:**
```ruby
# Gemfile
gem "sentry-ruby"
gem "sentry-rails"
```

**Next.js:**
```bash
npm install @sentry/nextjs
```

---

## Future Considerations

### Scaling Beyond SQLite

If usage grows significantly:
1. **Litestream** - Stream SQLite changes to S3 for backup and read replicas
2. **PostgreSQL** - Migration for full horizontal scaling
3. **Background Jobs** - Sidekiq/GoodJob for async GitHub fetching

### Performance Optimization

**SprintLoader Transaction Scope (from performance review):**

Current code runs GitHub API fetch inside a database transaction, causing blocking. Recommended fix:

```ruby
# Move fetch OUTSIDE transaction
def load(start_date, end_date, force: false)
  sprint = Sprint.find_by_dates(start_date, end_date)
  return sprint if sprint && !force

  # Fetch OUTSIDE transaction
  data = @fetcher.fetch_sprint_data(start_date, end_date)

  # Quick transaction for DB write only
  Sprint.transaction do
    sprint = Sprint.find_by_dates(start_date, end_date)
    if sprint
      sprint.update!(data: data)
    else
      sprint = Sprint.create!(start_date: start_date, end_date: end_date, data: data)
    end
  end
  sprint
end
```

---

## Research Sources

**Coolify Documentation:**
- [Health Checks](https://coolify.io/docs/knowledge-base/health-checks)
- [Rolling Updates](https://coolify.io/docs/knowledge-base/rolling-updates)
- [Persistent Storage](https://coolify.io/docs/knowledge-base/persistent-storage)
- [Dockerfile Build Pack](https://coolify.io/docs/applications/build-packs/dockerfile)

**Next.js Documentation (Context7):**
- [Standalone Output Mode](https://nextjs.org/docs/app/api-reference/next-config-js/output)
- [Docker Deployment](https://nextjs.org/docs/app/building-your-application/deploying)

**Rails 8 Guides (Context7):**
- [Host Configuration](https://guides.rubyonrails.org/configuring.html)
- [Force SSL](https://guides.rubyonrails.org/action_controller_overview.html)

**Community Resources:**
- [SQLite with Coolify - Samperalabs](https://samperalabs.com/posts/how-to-manage-sqlite-databases-on-a-vps-with-coolify)
- [Docker Layer Caching Fix - Loopwerk](https://www.loopwerk.io/articles/2025/coolify-docker-layer-caching/)
