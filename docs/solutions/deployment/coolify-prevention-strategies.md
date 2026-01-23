# Coolify Deployment Prevention Strategies

**Document Purpose:** Prevent common deployment failures when deploying Docker containers to Coolify.

**Issues Addressed:**
1. Docker BuildKit strict linting blocking builds with secrets in ARG/ENV
2. API-only Rails apps failing on `assets:precompile`
3. Alpine images missing `curl` for health checks

---

## Quick Reference: Pre-Deployment Checklist

Before deploying ANY Docker container to Coolify, verify:

- [ ] Dockerfile has BuildKit secret linting directive (if using secrets)
- [ ] No `assets:precompile` for API-only Rails apps
- [ ] Alpine images include `curl` for health checks
- [ ] Health check endpoint exists and is unauthenticated
- [ ] Production environment allows Coolify health check host

---

## Issue 1: Docker BuildKit Strict Linting

### The Problem

Modern Docker BuildKit (default in Coolify) enforces strict linting. Using secrets in `ARG` or `ENV` instructions triggers build failures:

```
ERROR: failed to solve: Dockerfile:42: secrets should not be used in ARG or ENV
```

### Detection

Search your Dockerfile for potential violations:

```bash
# Check for secrets in ARG/ENV
grep -E "^(ARG|ENV).*(SECRET|TOKEN|KEY|PASSWORD|CREDENTIAL)" Dockerfile
```

**Red flags:**
- `ARG GH_TOKEN`
- `ENV RAILS_MASTER_KEY=$MASTER_KEY`
- `ARG API_KEY`

### Prevention

**Option 1: Skip the lint check (Recommended for existing Dockerfiles)**

Add this directive at the top of your Dockerfile:

```dockerfile
# syntax=docker/dockerfile:1
# check=error=true;skip=SecretsUsedInArgOrEnv

FROM ruby:3.4-slim AS base
...
```

**Option 2: Use Docker secrets (Build-time only)**

```dockerfile
# syntax=docker/dockerfile:1

RUN --mount=type=secret,id=gh_token \
    GH_TOKEN=$(cat /run/secrets/gh_token) && \
    bundle install
```

**Option 3: Pass secrets at runtime only**

Never use secrets during build. Pass them as environment variables in Coolify's UI.

### Example Fix

**Before (fails):**
```dockerfile
ARG RAILS_MASTER_KEY
ENV RAILS_MASTER_KEY=$RAILS_MASTER_KEY
RUN bundle exec rails assets:precompile
```

**After (works):**
```dockerfile
# syntax=docker/dockerfile:1
# check=error=true;skip=SecretsUsedInArgOrEnv

ARG RAILS_MASTER_KEY
ENV RAILS_MASTER_KEY=$RAILS_MASTER_KEY
RUN bundle exec rails assets:precompile
```

---

## Issue 2: API-Only Rails Apps and assets:precompile

### The Problem

Rails 8's default Dockerfile includes `assets:precompile`, but API-only Rails apps have no asset pipeline. This causes build failures:

```
Don't know how to build task 'assets:precompile'
```

### Detection

Check if your Rails app is API-only:

```bash
# In your Rails app directory
grep -r "config.api_only = true" config/application.rb

# Check if asset pipeline gems exist
grep -E "(sprockets|propshaft)" Gemfile
```

**If API-only and no asset gems:** You must skip `assets:precompile`.

### Prevention

**Remove or comment out the assets:precompile line in Dockerfile:**

```dockerfile
# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile app/ lib/

# Note: Skipping assets:precompile - this is an API-only Rails app (no asset pipeline)
# RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile
```

### Validation Script

```bash
#!/bin/bash
# validate-rails-dockerfile.sh

# Check if API-only
if grep -q "config.api_only = true" config/application.rb; then
    echo "API-only Rails app detected"

    # Check Dockerfile for assets:precompile
    if grep -q "assets:precompile" Dockerfile; then
        echo "WARNING: Dockerfile contains assets:precompile but app is API-only"
        echo "This will fail in production. Remove or comment out the line."
        exit 1
    else
        echo "OK: No assets:precompile in Dockerfile"
    fi
fi
```

---

## Issue 3: Alpine Images Missing curl

### The Problem

Alpine Linux images are minimal and don't include `curl`. Coolify's health checks require an HTTP client:

```
Health check failed: curl: not found
```

### Detection

Check if your Dockerfile uses Alpine:

```bash
# Check base image
grep -E "FROM.*alpine" Dockerfile frontend/Dockerfile api/Dockerfile
```

**Common Alpine images:**
- `node:22-alpine`
- `ruby:3.4-alpine`
- `python:3.12-alpine`

### Prevention

**Install curl in the runner/production stage:**

```dockerfile
# Stage 3: Production runner
FROM node:22-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production

# Install curl for health checks (required by Coolify)
RUN apk add --no-cache curl

# ... rest of Dockerfile
```

**Key points:**
- Install in the FINAL stage (runner/production), not build stages
- Use `apk add --no-cache` to keep image small
- Add comment explaining why curl is needed

### Alternative: Use wget

Alpine includes `wget` by default. If you can't add packages, configure Coolify to use wget:

```bash
# In Coolify health check command:
wget -q --spider http://localhost:3000/health || exit 1
```

### Complete Alpine Health Check Pattern

```dockerfile
FROM node:22-alpine AS runner
WORKDIR /app

# Install curl for health checks (required by Coolify)
RUN apk add --no-cache curl

# Create non-root user
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

# ... copy files ...

USER nextjs

# Ensure health endpoint is accessible
EXPOSE 3000
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

# Health check (for Docker, Coolify uses its own)
# HEALTHCHECK --interval=30s --timeout=10s --start-period=30s \
#   CMD curl -f http://localhost:3000/api/health || exit 1

CMD ["node", "server.js"]
```

---

## Dockerfile Best Practices for Coolify

### 1. Always Include BuildKit Syntax Header

```dockerfile
# syntax=docker/dockerfile:1
# check=error=true;skip=SecretsUsedInArgOrEnv
```

### 2. Health Check Endpoint Requirements

Your app MUST have a health check endpoint that:
- Returns HTTP 200 on success
- Does NOT require authentication
- Is fast (< 5 seconds response)
- Is lightweight (minimal computation)

**Rails (use built-in /up endpoint):**
```ruby
# config/routes.rb - Rails 8 default
get "up" => "rails/health#show", as: :rails_health_check
```

**Next.js (create dedicated endpoint):**
```typescript
// src/app/api/health/route.ts
export async function GET() {
  return Response.json({ status: 'ok' });
}
```

### 3. Exclude Health Endpoint from Host Authorization

```ruby
# config/environments/production.rb
config.hosts << "your-domain.com"
config.host_authorization = {
  exclude: ->(request) { request.path == "/up" }
}
```

### 4. Multi-Stage Build Template

```dockerfile
# syntax=docker/dockerfile:1
# check=error=true;skip=SecretsUsedInArgOrEnv

# === BASE ===
FROM ruby:3.4-slim AS base
WORKDIR /app
# Install runtime dependencies including curl
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl && \
    rm -rf /var/lib/apt/lists/*

# === BUILD ===
FROM base AS build
# Install build dependencies
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git && \
    rm -rf /var/lib/apt/lists/*
COPY Gemfile* ./
RUN bundle install
COPY . .
# Skip assets:precompile for API-only apps
# RUN bundle exec rails assets:precompile

# === PRODUCTION ===
FROM base AS production
# curl is already in base image
COPY --from=build /app /app
EXPOSE 3000
CMD ["./bin/rails", "server"]
```

---

## Pre-Deployment Validation Script

Save as `scripts/validate-coolify-deployment.sh`:

```bash
#!/bin/bash
set -e

echo "=== Coolify Deployment Validation ==="

ERRORS=0

# Check 1: BuildKit directive
echo -n "Checking BuildKit directive... "
if head -5 Dockerfile | grep -q "check=error=true"; then
    echo "OK"
else
    echo "WARNING: Missing BuildKit lint skip directive"
    echo "  Add: # check=error=true;skip=SecretsUsedInArgOrEnv"
    ERRORS=$((ERRORS + 1))
fi

# Check 2: Secrets in ARG/ENV
echo -n "Checking for secrets in ARG/ENV... "
SECRETS_FOUND=$(grep -E "^(ARG|ENV).*(SECRET|TOKEN|KEY|PASSWORD)" Dockerfile 2>/dev/null || true)
if [ -n "$SECRETS_FOUND" ]; then
    echo "WARNING"
    echo "  Found potential secrets:"
    echo "$SECRETS_FOUND"
    echo "  Ensure BuildKit directive is present"
    ERRORS=$((ERRORS + 1))
else
    echo "OK"
fi

# Check 3: Alpine + curl
echo -n "Checking Alpine curl requirement... "
if grep -q "alpine" Dockerfile; then
    if grep -q "apk add.*curl" Dockerfile; then
        echo "OK"
    else
        echo "ERROR: Alpine image without curl"
        echo "  Add: RUN apk add --no-cache curl"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo "N/A (not Alpine)"
fi

# Check 4: API-only assets:precompile
echo -n "Checking assets:precompile for API-only... "
if [ -f "config/application.rb" ]; then
    if grep -q "config.api_only = true" config/application.rb; then
        if grep -q "assets:precompile" Dockerfile; then
            echo "ERROR: API-only app with assets:precompile"
            echo "  Remove or comment out the assets:precompile line"
            ERRORS=$((ERRORS + 1))
        else
            echo "OK"
        fi
    else
        echo "N/A (not API-only)"
    fi
else
    echo "N/A (not Rails)"
fi

# Check 5: Health endpoint
echo -n "Checking health endpoint exists... "
if [ -f "config/routes.rb" ]; then
    if grep -q 'health' config/routes.rb || grep -q '/up' config/routes.rb; then
        echo "OK"
    else
        echo "WARNING: No health endpoint found in routes"
        ERRORS=$((ERRORS + 1))
    fi
elif [ -f "src/app/api/health/route.ts" ]; then
    echo "OK"
else
    echo "WARNING: Could not verify health endpoint"
fi

echo ""
if [ $ERRORS -gt 0 ]; then
    echo "=== $ERRORS issue(s) found. Review before deploying. ==="
    exit 1
else
    echo "=== All checks passed! Ready for Coolify deployment. ==="
fi
```

---

## Coolify-Specific Configuration

### Health Check Settings in Coolify UI

| Setting | Recommended Value | Notes |
|---------|-------------------|-------|
| Health Check Path | `/up` (Rails) or `/api/health` (Next.js) | Must be unauthenticated |
| Interval | 30 seconds | Balance between detection and overhead |
| Timeout | 10 seconds | Allow for slow cold starts |
| Start Period | 30 seconds | Critical for container initialization |
| Retries | 3 | Avoid flapping on transient failures |

### Environment Variables in Coolify

**DO:** Set sensitive values in Coolify UI
- `RAILS_MASTER_KEY`
- `GH_TOKEN`
- `DATABASE_URL`
- OAuth secrets

**DON'T:** Bake secrets into the image via `ARG`/`ENV` in Dockerfile

---

## Common Failure Patterns

| Symptom | Likely Cause | Solution |
|---------|--------------|----------|
| Build fails with "secrets should not be used" | BuildKit strict mode | Add `skip=SecretsUsedInArgOrEnv` directive |
| Build fails with "Don't know how to build task 'assets:precompile'" | API-only Rails app | Remove assets:precompile from Dockerfile |
| Health check fails with "curl: not found" | Alpine image without curl | Add `RUN apk add --no-cache curl` |
| Health check 404 | Endpoint doesn't exist | Create `/up` or `/api/health` endpoint |
| Health check 403 | Host authorization blocking | Add `exclude` for health check path |
| Health check timeout | Start period too short | Increase to 30-60 seconds |

---

## References

- [Coolify Health Checks Documentation](https://coolify.io/docs/knowledge-base/health-checks)
- [Docker BuildKit Syntax](https://docs.docker.com/engine/reference/builder/#syntax)
- [Rails Health Check Endpoint](https://guides.rubyonrails.org/configuring.html#config-x-healthcheck)
- [Next.js Route Handlers](https://nextjs.org/docs/app/building-your-application/routing/route-handlers)
