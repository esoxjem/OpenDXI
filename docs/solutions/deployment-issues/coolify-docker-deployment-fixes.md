---
title: "Fix Coolify deployment failures for Rails API + Next.js monorepo"
category: deployment-issues
tags:
  - coolify
  - docker
  - rails
  - nextjs
  - alpine
  - health-checks
  - buildkit
  - dockerfile
  - api-only-rails
  - multi-stage-build
severity: medium
date_solved: 2026-01-23
components_affected:
  - api/Dockerfile
  - frontend/Dockerfile
related_errors:
  - "lint violation found for rules: SecretsUsedInArgOrEnv"
  - "Unrecognized command 'assets:precompile'"
  - "/bin/sh: curl: not found"
  - "Container status: exited:unhealthy"
symptoms:
  - Rails API build fails with BuildKit lint error about secrets
  - Rails build fails trying to precompile assets on API-only app
  - Next.js container starts but health checks fail
  - Container shows exited:unhealthy status in Coolify
root_causes:
  - Docker BuildKit treats SecretsUsedInArgOrEnv warning as error
  - Rails 8 default Dockerfile includes assets:precompile for full apps
  - Alpine-based Node images don't include curl by default
related_docs:
  - plans/feat-deploy-to-coolify.md
  - plans/deployment-verification-checklist.md
---

# Fix Coolify Deployment Failures for Rails API + Next.js Monorepo

When deploying a Rails 8 API + Next.js frontend monorepo to Coolify using Docker, you may encounter three distinct build/health check failures. This document covers all three issues, their root causes, and working solutions.

## Problem Summary

| Issue | Symptom | Root Cause |
|-------|---------|------------|
| 1 | Build fails: `SecretsUsedInArgOrEnv` | BuildKit strict linting |
| 2 | Build fails: `assets:precompile` not found | API-only Rails has no asset pipeline |
| 3 | Health check fails: `curl: not found` | Alpine images are minimal |

## Issue 1: Docker BuildKit SecretsUsedInArgOrEnv Lint Error

### Symptom

Build fails with error:
```
ERROR: failed to build: failed to solve: lint violation found for rules: SecretsUsedInArgOrEnv
```

With warnings like:
```
SecretsUsedInArgOrEnv: Do not use ARG or ENV instructions for sensitive data (ARG "RAILS_MASTER_KEY")
SecretsUsedInArgOrEnv: Do not use ARG or ENV instructions for sensitive data (ARG "GH_TOKEN")
```

### Root Cause

The Dockerfile has `# check=error=true` which instructs Docker BuildKit to treat all lint warnings as errors. The `SecretsUsedInArgOrEnv` rule flags build arguments that might contain secrets.

In multi-stage builds, ARGs in build stages don't persist to the final image, so this is often a false positive.

### Solution

Modify line 2 of the Dockerfile to skip the specific lint rule:

**Before:**
```dockerfile
# syntax=docker/dockerfile:1
# check=error=true
```

**After:**
```dockerfile
# syntax=docker/dockerfile:1
# check=error=true;skip=SecretsUsedInArgOrEnv
```

### Why This Works

- Keeps strict linting for all other rules
- Skips only the false positive for secrets in build arguments
- Multi-stage builds ensure ARGs don't leak to final image

---

## Issue 2: Rails assets:precompile Not Found

### Symptom

Build fails with:
```
Unrecognized command "assets:precompile" (Rails::Command::UnrecognizedCommandError)
```

### Root Cause

API-only Rails applications (generated with `rails new --api`) do not include the asset pipeline (Sprockets or Propshaft). The `assets:precompile` command is only available in full Rails applications.

The default Rails 8 Dockerfile is generated for full-stack apps and includes:
```dockerfile
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile
```

### Solution

Remove or comment out the asset precompilation line:

**Before:**
```dockerfile
# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile
```

**After:**
```dockerfile
# Note: Skipping assets:precompile - this is an API-only Rails app (no asset pipeline)
```

### How to Detect API-Only Rails Apps

Check `config/application.rb` for:
```ruby
config.api_only = true
```

Or check if the Gemfile lacks `sprockets-rails` or `propshaft`.

---

## Issue 3: Frontend Health Check Failure (curl not found)

### Symptom

Container shows status `exited:unhealthy` with error in logs:
```
/bin/sh: curl: not found
wget: can't connect to remote host: Connection refused
```

### Root Cause

Coolify uses `curl` for HTTP health checks by default. Alpine-based Node.js images (`node:XX-alpine`) are minimal and do not include `curl`.

### Solution

Add `curl` installation to the runner stage of your Next.js Dockerfile:

**Before:**
```dockerfile
FROM base AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

# Create non-root user
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs
```

**After:**
```dockerfile
FROM base AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

# Install curl for health checks (required by Coolify)
RUN apk add --no-cache curl

# Create non-root user
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs
```

### Why `--no-cache`?

The `--no-cache` flag:
- Prevents storing the package index in the image
- Keeps the final image size minimal
- Is the Alpine best practice for single package installs

---

## Complete Working Dockerfiles

### Rails API Dockerfile (`api/Dockerfile`)

Key sections with fixes applied:

```dockerfile
# syntax=docker/dockerfile:1
# check=error=true;skip=SecretsUsedInArgOrEnv

ARG RUBY_VERSION=3.4.3
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

# ... (base stage setup)

FROM base AS build

# ... (build dependencies, gem installation, copy application)

# Precompile bootsnap
RUN bundle exec bootsnap precompile -j 1 app/ lib/

# Note: Skipping assets:precompile - this is an API-only Rails app (no asset pipeline)

FROM base

# ... (final stage)
```

### Next.js Frontend Dockerfile (`frontend/Dockerfile`)

Key sections with fixes applied:

```dockerfile
FROM node:22-alpine AS base

# ... (deps and builder stages)

FROM base AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

# Install curl for health checks (required by Coolify)
RUN apk add --no-cache curl

# Create non-root user
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

# ... (copy standalone build, set user, expose port)

CMD ["node", "server.js"]
```

---

## Prevention Checklist

Before deploying to Coolify, verify:

- [ ] **BuildKit linting**: If using `check=error=true`, add `skip=SecretsUsedInArgOrEnv` if passing secrets as ARGs
- [ ] **API-only Rails**: Remove `assets:precompile` from Dockerfile
- [ ] **Alpine images**: Install `curl` for health checks (`apk add --no-cache curl`)
- [ ] **Health endpoint**: Ensure health check endpoint exists and is unauthenticated
- [ ] **Host authorization**: Rails `config.hosts` allows Coolify health check requests

## Coolify CLI Deployment Commands

For reference, here are the CLI commands used:

```bash
# Create project
coolify project create --name "OpenDXI"

# Create apps
coolify app create public \
  --server-uuid <uuid> \
  --project-uuid <uuid> \
  --git-repository "https://github.com/user/repo" \
  --git-branch main \
  --build-pack dockerfile \
  --base-directory "/api" \
  --name "OpenDXI API" \
  --ports-exposes 80 \
  --domains "https://dxi-api.example.com"

# Sync environment variables
coolify app env sync <app-uuid> --file .env

# Deploy
coolify deploy uuid <app-uuid>

# Check logs
coolify app deployments logs <app-uuid> <deployment-uuid> --debuglogs
```

## Related Documentation

- [Coolify Deployment Plan](../../../plans/feat-deploy-to-coolify.md)
- [Deployment Verification Checklist](../../../plans/deployment-verification-checklist.md)
- [Coolify CLI Documentation](https://coolify.io/docs)
- [Docker BuildKit Linting](https://docs.docker.com/build/checks/)

## Commits That Fixed These Issues

- `89f48f9` - fix(docker): Skip SecretsUsedInArgOrEnv lint check
- `83e25f8` - fix(docker): Remove assets:precompile for API-only Rails app
- `5f45443` - fix(docker): Add curl to frontend for Coolify health checks
