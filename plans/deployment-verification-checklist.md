# Deployment Verification Checklist: OpenDXI to Coolify

**Deployment Target:**
- Frontend: https://dxi.esoxjem.com
- API: https://dxi-api.esoxjem.com
- Date: _______________
- Deployer: _______________

---

## Pre-Deploy (Required)

### 1. Code Preparation Verification

- [ ] Frontend Dockerfile exists at `frontend/Dockerfile`
- [ ] `frontend/next.config.ts` has `output: "standalone"`
- [ ] `frontend/.dockerignore` exists
- [ ] `api/config/environments/production.rb` includes `dxi-api.esoxjem.com` in allowed hosts
- [ ] `api/config/initializers/github.rb` validates GH_TOKEN presence
- [ ] `api/config/database.yml` production section is simplified (single database)

**Verification Commands (run locally):**
```bash
# Check frontend Dockerfile exists
ls -la frontend/Dockerfile

# Check standalone output config
grep -r "standalone" frontend/next.config.ts

# Check allowed hosts
grep -r "dxi-api.esoxjem.com" api/config/environments/production.rb

# Check GH_TOKEN validation
cat api/config/initializers/github.rb
```

### 2. Environment Variables Prepared

**Rails API (all required):**

| Variable | Value Set | Notes |
|----------|-----------|-------|
| `RAILS_MASTER_KEY` | [ ] | From `api/config/master.key` |
| `GITHUB_ORG` | [ ] | Your GitHub organization name |
| `GH_TOKEN` | [ ] | PAT with `repo` and `read:org` scopes |
| `CORS_ORIGINS` | [ ] | Must be `https://dxi.esoxjem.com` |
| `GITHUB_OAUTH_CLIENT_ID` | [ ] | From GitHub OAuth App |
| `GITHUB_OAUTH_CLIENT_SECRET` | [ ] | From GitHub OAuth App |
| `GITHUB_OAUTH_CALLBACK_URL` | [ ] | Must be `https://dxi-api.esoxjem.com/auth/github/callback` |
| `FRONTEND_URL` | [ ] | Must be `https://dxi.esoxjem.com` |

**Next.js Frontend (build argument):**

| Variable | Value Set | Notes |
|----------|-----------|-------|
| `NEXT_PUBLIC_API_URL` | [ ] | Must be `https://dxi-api.esoxjem.com` |

**Pre-Deploy Validation:**
```bash
# Verify GH_TOKEN has correct scopes (run locally)
curl -H "Authorization: token YOUR_GH_TOKEN" \
  https://api.github.com/user \
  -s | jq '.login'
# Expected: Your GitHub username

# Verify GH_TOKEN can access organization
curl -H "Authorization: token YOUR_GH_TOKEN" \
  "https://api.github.com/orgs/YOUR_ORG/members" \
  -s | jq '.[0].login'
# Expected: First member's username (not null/error)
```

### 3. DNS Configuration Verification

**Required DNS Records:**
```
dxi.esoxjem.com      A    <coolify-server-ip>
dxi-api.esoxjem.com  A    <coolify-server-ip>
```

**DNS Propagation Check:**
```bash
# Check DNS resolution
dig +short dxi.esoxjem.com
# Expected: Coolify server IP

dig +short dxi-api.esoxjem.com
# Expected: Coolify server IP

# Alternative check using nslookup
nslookup dxi.esoxjem.com
nslookup dxi-api.esoxjem.com
```

- [ ] DNS A record for `dxi.esoxjem.com` resolves to Coolify server IP
- [ ] DNS A record for `dxi-api.esoxjem.com` resolves to Coolify server IP
- [ ] DNS propagation complete (check from multiple locations)

**Multi-location DNS Check:**
```bash
# Check from Google DNS
dig @8.8.8.8 +short dxi.esoxjem.com
dig @8.8.8.8 +short dxi-api.esoxjem.com

# Check from Cloudflare DNS
dig @1.1.1.1 +short dxi.esoxjem.com
dig @1.1.1.1 +short dxi-api.esoxjem.com
```

### 4. Coolify Configuration Checklist

**Rails API Resource:**
- [ ] Repository URL correct
- [ ] Branch set to `main`
- [ ] Build Pack: Dockerfile
- [ ] Base Directory: `/api`
- [ ] Dockerfile Location: `/api/Dockerfile`
- [ ] Watch Paths: `api/**`
- [ ] Domain: `https://dxi-api.esoxjem.com`
- [ ] Volume mounted: `opendxi-rails-storage` -> `/rails/storage`
- [ ] Health Check Path: `/up`
- [ ] Health Check Interval: 30s
- [ ] **Max Instances: 1** (CRITICAL - SQLite constraint)
- [ ] All environment variables set

**Next.js Frontend Resource:**
- [ ] Repository URL correct
- [ ] Branch set to `main`
- [ ] Build Pack: Dockerfile
- [ ] Base Directory: `/frontend`
- [ ] Dockerfile Location: `/frontend/Dockerfile`
- [ ] Watch Paths: `frontend/**`
- [ ] Domain: `https://dxi.esoxjem.com`
- [ ] Health Check Path: `/`
- [ ] Health Check Interval: 30s
- [ ] Build argument `NEXT_PUBLIC_API_URL` set

---

## Deploy Steps

### 5. Deploy Sequence

1. [ ] Deploy Rails API first (API must be available before frontend makes requests)
2. [ ] Wait for API health check to pass in Coolify dashboard
3. [ ] Deploy Next.js Frontend
4. [ ] Wait for Frontend health check to pass in Coolify dashboard

**Monitor Deployment Logs:**
- [ ] Rails API build completes without errors
- [ ] Rails API container starts successfully
- [ ] Next.js Frontend build completes without errors
- [ ] Next.js Frontend container starts successfully

---

## Post-Deploy (Within 5 Minutes)

### 6. SSL Certificate Verification

```bash
# Check SSL certificate for API
echo | openssl s_client -connect dxi-api.esoxjem.com:443 -servername dxi-api.esoxjem.com 2>/dev/null | openssl x509 -noout -dates
# Expected: notBefore and notAfter dates showing valid certificate

# Check SSL certificate for Frontend
echo | openssl s_client -connect dxi.esoxjem.com:443 -servername dxi.esoxjem.com 2>/dev/null | openssl x509 -noout -dates
# Expected: notBefore and notAfter dates showing valid certificate

# Verify certificate issuer (should be Let's Encrypt)
echo | openssl s_client -connect dxi-api.esoxjem.com:443 -servername dxi-api.esoxjem.com 2>/dev/null | openssl x509 -noout -issuer
# Expected: issuer= ... Let's Encrypt ...
```

- [ ] API SSL certificate valid and auto-provisioned
- [ ] Frontend SSL certificate valid and auto-provisioned
- [ ] No certificate warnings in browser

### 7. API Endpoint Testing

**Health Check:**
```bash
curl -s https://dxi-api.esoxjem.com/api/health | jq .
# Expected:
# {
#   "status": "ok",
#   "version": "..."
# }
```
- [ ] Health endpoint returns `status: ok`

**Rails Health Check (Coolify uses this):**
```bash
curl -s https://dxi-api.esoxjem.com/up
# Expected: HTTP 200 (may return HTML or empty body)

curl -I https://dxi-api.esoxjem.com/up
# Expected: HTTP/2 200
```
- [ ] `/up` endpoint returns HTTP 200

**Config Endpoint:**
```bash
curl -s https://dxi-api.esoxjem.com/api/config | jq .
# Expected:
# {
#   "github_org": "your-org",
#   "sprint_start_date": "...",
#   "sprint_duration_days": 14,
#   ...
# }
```
- [ ] Config endpoint returns correct `github_org`
- [ ] Config endpoint returns expected sprint configuration

**Sprints Endpoint:**
```bash
curl -s https://dxi-api.esoxjem.com/api/sprints | jq .
# Expected: Array of sprint objects with start_date, end_date
```
- [ ] Sprints endpoint returns list of sprints

### 8. Frontend Loading Verification

**HTTP Response Check:**
```bash
curl -I https://dxi.esoxjem.com
# Expected:
# HTTP/2 200
# content-type: text/html
```
- [ ] Frontend returns HTTP 200
- [ ] Content-Type is text/html

**Page Content Check:**
```bash
curl -s https://dxi.esoxjem.com | head -50
# Expected: HTML with Next.js app structure
# Look for: <div id="__next"> or similar React root
```
- [ ] HTML contains React app root element

**JavaScript Loading:**
```bash
curl -s https://dxi.esoxjem.com | grep -o '_next/static/.*\.js' | head -5
# Expected: JavaScript bundle paths
```
- [ ] JavaScript bundles are referenced in HTML

### 9. CORS Verification

**Preflight Request Test:**
```bash
curl -I -X OPTIONS https://dxi-api.esoxjem.com/api/health \
  -H "Origin: https://dxi.esoxjem.com" \
  -H "Access-Control-Request-Method: GET" \
  -H "Access-Control-Request-Headers: Content-Type"
# Expected:
# HTTP/2 204 or 200
# access-control-allow-origin: https://dxi.esoxjem.com
# access-control-allow-methods: GET, POST, PUT, PATCH, DELETE, OPTIONS
```
- [ ] CORS preflight returns 204 or 200
- [ ] `access-control-allow-origin` header present
- [ ] Origin matches frontend domain exactly

**Actual Request with Origin:**
```bash
curl -s https://dxi-api.esoxjem.com/api/health \
  -H "Origin: https://dxi.esoxjem.com" \
  -D - | head -20
# Expected: access-control-allow-origin header in response
```
- [ ] CORS headers present in actual requests

**Browser Console Check (manual):**
1. Open https://dxi.esoxjem.com in browser
2. Open Developer Tools (F12) -> Console tab
3. Look for CORS errors

- [ ] No CORS errors in browser console

### 10. GitHub Integration Testing

**API Can Reach GitHub:**
```bash
# Test metrics endpoint (will fetch from GitHub if not cached)
curl -s "https://dxi-api.esoxjem.com/api/sprints/2026-01-07/2026-01-20/metrics" | jq '.team_metrics.total_prs'
# Expected: Number (0 or more)
```
- [ ] Metrics endpoint returns data
- [ ] No GitHub authentication errors in API logs

**Force Refresh Test:**
```bash
curl -s "https://dxi-api.esoxjem.com/api/sprints/2026-01-07/2026-01-20/metrics?force_refresh=true" | jq '.team_metrics'
# Expected: Fresh data from GitHub
```
- [ ] Force refresh triggers new GitHub fetch
- [ ] No errors during refresh

### 11. Volume Persistence Verification

**Initial Data Check:**
```bash
# Make a request that creates data
curl -s "https://dxi-api.esoxjem.com/api/sprints/2026-01-07/2026-01-20/metrics" > /dev/null

# Note the current time
date
```
- [ ] Initial metrics request completed

**Restart Container (in Coolify UI):**
1. Go to Rails API resource in Coolify
2. Click Restart
3. Wait for health check to pass

**Post-Restart Verification:**
```bash
# Request same data again (should be cached, not re-fetched from GitHub)
time curl -s "https://dxi-api.esoxjem.com/api/sprints/2026-01-07/2026-01-20/metrics" > /dev/null
# Expected: Fast response (< 1 second) indicating cached data
```
- [ ] Data persisted after container restart
- [ ] Response time indicates cached data was used

---

## Full End-to-End Verification (Manual)

### 12. Browser Testing

1. [ ] Open https://dxi.esoxjem.com in browser
2. [ ] Page loads without errors
3. [ ] Dashboard UI renders correctly
4. [ ] Sprint selector/date picker works
5. [ ] Metrics data loads and displays
6. [ ] Charts/visualizations render
7. [ ] Leaderboard shows developer data
8. [ ] No JavaScript errors in console
9. [ ] No network errors in Network tab
10. [ ] Responsive design works (test mobile view)

### 13. Authentication Flow (if applicable)

```bash
# Check auth status endpoint
curl -s https://dxi-api.esoxjem.com/api/auth/me
# Expected: Unauthenticated response or redirect
```
- [ ] Auth endpoints respond correctly
- [ ] OAuth flow works (if configured)

---

## Rollback Plan

### If Deployment Fails

**Immediate Actions:**
1. [ ] Check Coolify deployment logs for errors
2. [ ] Check container logs for runtime errors
3. [ ] Verify environment variables are correct

**Rollback Steps:**

**Code Rollback:**
```bash
# Identify last working commit
git log --oneline -10

# Create rollback branch or tag
git checkout <last-working-commit>
git push origin HEAD:rollback-branch

# In Coolify: Change branch to rollback-branch and redeploy
```

**Environment Variable Issues:**
1. In Coolify, go to resource settings
2. Verify all environment variables
3. Redeploy after fixing

**Volume/Data Issues:**
1. Check Coolify volume configuration
2. Verify volume mount path is `/rails/storage`
3. If data corrupted, delete volume and redeploy (data will be re-fetched from GitHub)

### Rollback Verification

After rollback:
```bash
# Verify API is responding
curl -s https://dxi-api.esoxjem.com/api/health | jq .

# Verify frontend loads
curl -I https://dxi.esoxjem.com
```

---

## Monitoring Setup (First 24 Hours)

### 14. Health Check Monitoring

**Automated Checks in Coolify:**
- [ ] API health check configured (path: `/up`, interval: 30s)
- [ ] Frontend health check configured (path: `/`, interval: 30s)
- [ ] Alerts configured for health check failures (if available)

### 15. Manual Monitoring Schedule

| Time After Deploy | Actions |
|-------------------|---------|
| +15 minutes | Run all post-deploy verification commands |
| +1 hour | Full browser test, check error logs |
| +4 hours | Verify data persistence, check for errors |
| +24 hours | Review any accumulated errors, close ticket |

### 16. Log Monitoring

**Check API Logs (in Coolify):**
- [ ] No repeated errors
- [ ] No authentication failures
- [ ] No database errors
- [ ] No memory/resource issues

**Error Patterns to Watch:**
```
# Look for these in logs:
- "GH_TOKEN" - Token issues
- "CORS" - Cross-origin problems
- "SQLite" - Database issues
- "ActiveRecord" - ORM errors
- "500" - Server errors
- "timeout" - Performance issues
```

### 17. Performance Baseline

**Establish baseline response times:**
```bash
# API health check (should be < 100ms)
time curl -s https://dxi-api.esoxjem.com/api/health > /dev/null

# Frontend load (should be < 2s)
time curl -s https://dxi.esoxjem.com > /dev/null

# Cached metrics (should be < 500ms)
time curl -s "https://dxi-api.esoxjem.com/api/sprints/2026-01-07/2026-01-20/metrics" > /dev/null
```

**Record baseline values:**
- API health: _______ ms
- Frontend load: _______ ms
- Metrics (cached): _______ ms

---

## Deployment Sign-Off

### Go/No-Go Decision

**GO Criteria (all must pass):**
- [ ] All pre-deploy checks completed
- [ ] Both services deployed successfully
- [ ] Health checks passing
- [ ] SSL certificates valid
- [ ] CORS working correctly
- [ ] GitHub integration functional
- [ ] Data persistence verified
- [ ] End-to-end browser test passed

**Deployment Status:** [ ] GO / [ ] NO-GO

**Sign-off:**
- Deployer: _______________
- Date/Time: _______________
- Notes: _______________

---

## Quick Reference Commands

```bash
# === Health Checks ===
curl -s https://dxi-api.esoxjem.com/api/health | jq .
curl -I https://dxi.esoxjem.com

# === Config ===
curl -s https://dxi-api.esoxjem.com/api/config | jq .

# === Sprints ===
curl -s https://dxi-api.esoxjem.com/api/sprints | jq .

# === Metrics ===
curl -s "https://dxi-api.esoxjem.com/api/sprints/2026-01-07/2026-01-20/metrics" | jq '.team_metrics'

# === CORS Test ===
curl -I -X OPTIONS https://dxi-api.esoxjem.com/api/health \
  -H "Origin: https://dxi.esoxjem.com" \
  -H "Access-Control-Request-Method: GET"

# === SSL Check ===
echo | openssl s_client -connect dxi-api.esoxjem.com:443 2>/dev/null | openssl x509 -noout -dates

# === DNS Check ===
dig +short dxi.esoxjem.com
dig +short dxi-api.esoxjem.com
```

---

## Troubleshooting Guide

### Common Issues and Solutions

| Symptom | Possible Cause | Solution |
|---------|---------------|----------|
| API returns 502/503 | Container not running | Check Coolify logs, redeploy |
| CORS errors | Wrong CORS_ORIGINS | Update env var, redeploy |
| SSL errors | Certificate not provisioned | Wait 5 min, check DNS |
| GitHub auth errors | Invalid/expired GH_TOKEN | Regenerate token, update env |
| Data not persisting | Volume not mounted | Check volume config in Coolify |
| Slow responses | SQLite file locked | Verify max instances = 1 |
| Frontend can't reach API | Wrong NEXT_PUBLIC_API_URL | Rebuild frontend with correct URL |
| 500 errors | Missing RAILS_MASTER_KEY | Add env var, redeploy |

### Emergency Contacts

- Coolify Documentation: https://coolify.io/docs
- GitHub Status: https://www.githubstatus.com/
- Let's Encrypt Status: https://letsencrypt.status.io/
