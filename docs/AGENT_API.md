# OpenDXI Agent API Guide

This guide explains how agents (CLI tools, bots, automated systems) can interact with the OpenDXI API efficiently using HTTP caching and other optimization techniques.

## Table of Contents

1. [Authentication](#authentication)
2. [HTTP Caching (ETags)](#http-caching-etags)
3. [Endpoints](#endpoints)
4. [Error Handling](#error-handling)
5. [Code Examples](#code-examples)

---

## Authentication

### GitHub OAuth (Browser-Based)

For browser-based agents, use GitHub OAuth:

```bash
# Visit in browser:
https://your-app-domain/auth/github

# You'll be redirected back with session established
```

### Local Development

In local development, GitHub OAuth is bypassed for convenience:

```bash
# Local dev automatically authenticated
curl http://localhost:3000/api/health
```

### Future: API Keys

API key authentication for CLI/service accounts is planned but not yet implemented. Contact the team if you need this.

---

## HTTP Caching (ETags)

The metrics endpoint supports **ETag-based HTTP 304 Not Modified responses** for bandwidth optimization. This is critical for efficient agent usage.

### What is ETag Caching?

ETags (Entity Tags) are cache validators that allow agents to:
1. Request data once and receive full response with ETag header
2. On subsequent requests, send the ETag back
3. If data unchanged, server returns 304 Not Modified (empty body, ~400 bytes)
4. If data changed, server returns 200 OK with full response

**Bandwidth savings:** 50KB → 400 bytes for unchanged data (~99% reduction)

### How to Use ETag Caching

#### Step 1: First Request (Get the ETag)

```bash
curl -i http://localhost:3000/api/sprints/2026-01-07/2026-01-21/metrics

# Response headers include:
# HTTP/1.1 200 OK
# ETag: "42-a1b2c3d4e5f6g7h8i9j0-1674123456"
# Cache-Control: public, max-age=300
#
# Response body: {...full metrics JSON...} (~50KB)
```

#### Step 2: Subsequent Requests (Use the ETag)

```bash
# Save the ETag from step 1: "42-a1b2c3d4e5f6g7h8i9j0-1674123456"

curl -i -H 'If-None-Match: "42-a1b2c3d4e5f6g7h8i9j0-1674123456"' \
  http://localhost:3000/api/sprints/2026-01-07/2026-01-21/metrics

# Response headers include:
# HTTP/1.1 304 Not Modified
# ETag: "42-a1b2c3d4e5f6g7h8i9j0-1674123456"
#
# Response body: (empty) (~400 bytes)
```

#### Step 3: Handle Cache Invalidation

If the ETag doesn't match, the data has changed:

```bash
# If data was updated on server, ETag changes
curl -i -H 'If-None-Match: "42-OLD_ETAG-1674123456"' \
  http://localhost:3000/api/sprints/2026-01-07/2026-01-21/metrics

# Response headers:
# HTTP/1.1 200 OK
# ETag: "42-NEW_ETAG_HASH-1674124567"  # New ETag!
#
# Response body: {...updated metrics JSON...} (~50KB)

# Save the new ETag for next request
```

### Best Practices for ETag Caching

1. **Always send If-None-Match on repeat requests** - Enables 304 responses
2. **Cache both the ETag and response body locally** - Have data ready when 304 returned
3. **Handle 304 Not Modified status** - Treat as "use cached data"
4. **Update cached ETag after each response** - Store new ETag from response headers
5. **Respect Cache-Control: max-age** - Don't request before `max-age` expires (default: 5 min)

---

## Endpoints

### GET /api/health
Health check endpoint. Returns API version and status.

```bash
curl http://localhost:3000/api/health

# Response:
# {
#   "status": "ok",
#   "version": "1.0.0"
# }
```

### GET /api/config
Get GitHub organization configuration.

```bash
curl http://localhost:3000/api/config

# Response:
# {
#   "github_org": "your-org-name"
# }
```

### GET /api/sprints
List available sprints for dropdown selector.

**Caching:** 1 hour (`staleTime` in frontend, not ETag-cached)

```bash
curl http://localhost:3000/api/sprints

# Response:
# {
#   "sprints": [
#     {
#       "label": "Current Sprint",
#       "value": "2026-01-07|2026-01-21",
#       "start": "2026-01-07",
#       "end": "2026-01-21",
#       "is_current": true
#     },
#     {
#       "label": "Dec 24 - Jan 07",
#       "value": "2025-12-24|2026-01-07",
#       "start": "2025-12-24",
#       "end": "2026-01-07",
#       "is_current": false
#     }
#   ]
# }
```

### GET /api/sprints/{start_date}/{end_date}/metrics
Get metrics for a specific sprint.

**Parameters:**
- `start_date` - Sprint start (YYYY-MM-DD format)
- `end_date` - Sprint end (YYYY-MM-DD format)
- `force_refresh` (optional) - `true` to bypass cache and fetch fresh data

**Caching:** ETag-based 304 responses (see above)

**Rate Limiting:** `force_refresh=true` limited to 5 requests/hour per IP

```bash
# Basic request
curl http://localhost:3000/api/sprints/2026-01-07/2026-01-21/metrics

# With ETag (second request - gets 304)
curl -H 'If-None-Match: "42-hash-timestamp"' \
  http://localhost:3000/api/sprints/2026-01-07/2026-01-21/metrics

# Force fresh data (bypasses ETag check, triggers GitHub API fetch)
curl "http://localhost:3000/api/sprints/2026-01-07/2026-01-21/metrics?force_refresh=true"

# Response (200 OK):
# {
#   "developers": [
#     {
#       "developer": "alice",
#       "dxi_score": 75.5,
#       "commits": 12,
#       "prs_opened": 3,
#       "prs_merged": 3,
#       "reviews_given": 8,
#       ...
#     }
#   ],
#   "summary": {
#     "total_commits": 45,
#     "total_prs": 12,
#     "total_merged": 11,
#     "total_reviews": 28,
#     "developer_count": 4,
#     "avg_dxi_score": 72.1
#   },
#   "team_dimension_scores": {
#     "review_turnaround": 78.0,
#     "cycle_time": 72.0,
#     "pr_size": 85.0,
#     "review_coverage": 68.0,
#     "commit_frequency": 75.0
#   }
# }
```

### GET /api/sprints/history
Get sprint history for trend analysis.

**Parameters:**
- `count` (optional) - Number of sprints to return (default: 6, max: 12)

**Caching:** 1 hour

```bash
curl "http://localhost:3000/api/sprints/history?count=6"

# Response:
# {
#   "sprints": [
#     {
#       "start_date": "2025-12-10",
#       "end_date": "2025-12-23",
#       "avg_dxi_score": 68.5,
#       "total_commits": 42,
#       "total_prs": 10,
#       "developer_count": 4,
#       ...
#     },
#     ...
#   ]
# }
```

### GET /api/developers/{developer_name}/history
Get historical metrics for a specific developer.

**Parameters:**
- `count` (optional) - Number of sprints to return (default: 6, max: 12)

**Caching:** 1 hour

```bash
curl "http://localhost:3000/api/developers/alice/history?count=6"

# Response:
# {
#   "sprints": [...]
# }
```

---

## Error Handling

Agents should handle these HTTP status codes:

| Status | Meaning | Action |
|--------|---------|--------|
| 200 OK | Request successful, full data in response | Use the response body |
| 304 Not Modified | Data unchanged, use cached copy | Return previously cached response body |
| 400 Bad Request | Invalid date format or missing params | Check request parameters |
| 401 Unauthorized | Not authenticated | Re-authenticate via GitHub OAuth |
| 429 Too Many Requests | Rate limit exceeded (force_refresh only) | Wait before retrying (see Retry-After header) |

### 400 Bad Request Examples

```bash
# Invalid start_date format
curl http://localhost:3000/api/sprints/invalid-date/2026-01-21/metrics
# → 400 Bad Request

# Missing end_date
curl http://localhost:3000/api/sprints/2026-01-07/metrics
# → 400 Bad Request

# Completely invalid dates
curl http://localhost:3000/api/sprints/foo/bar/metrics
# → 400 Bad Request

# Response body:
# {
#   "error": "bad_request",
#   "detail": "Invalid date format"
# }
```

### 429 Too Many Requests (Rate Limit)

```bash
# Fifth force_refresh in one hour
curl "http://localhost:3000/api/sprints/2026-01-07/2026-01-21/metrics?force_refresh=true"
# → 429 Too Many Requests after 5th request

# Response headers:
# Retry-After: 3600
# X-RateLimit-Limit: 5
# X-RateLimit-Remaining: 0
# X-RateLimit-Reset: 1674124567

# Response body:
# {
#   "error": "rate_limited",
#   "detail": "Force refresh is limited to 5 requests per hour.",
#   "retry_after": 3600,
#   "reset_at": "2026-01-23T22:09:27Z"
# }
```

---

## Code Examples

### Python: ETag-Aware Client

```python
import requests
from urllib.parse import urljoin
from datetime import datetime, timedelta

class SprintMetricsClient:
    def __init__(self, base_url):
        self.base_url = base_url
        self.etags = {}
        self.cached_responses = {}
        self.cache_expiry = {}

    def get_metrics(self, start_date, end_date, force_refresh=False):
        """
        Get metrics for a sprint with ETag caching.

        Returns: (status_code, data)
        - 200: Fresh data
        - 304: Cached data (returned from self.cached_responses)
        """
        url = urljoin(
            self.base_url,
            f"/api/sprints/{start_date}/{end_date}/metrics"
        )

        cache_key = f"{start_date}:{end_date}"
        headers = {}

        # Add ETag from previous response if available
        if cache_key in self.etags and not force_refresh:
            headers["If-None-Match"] = self.etags[cache_key]

        # Add force_refresh parameter if requested
        params = {}
        if force_refresh:
            params["force_refresh"] = "true"

        try:
            response = requests.get(
                url,
                headers=headers,
                params=params,
                timeout=10
            )

            if response.status_code == 304:
                # Cache hit - return previously cached data
                print(f"✓ Cache hit: {cache_key}")
                return 304, self.cached_responses.get(cache_key)

            elif response.status_code == 200:
                # Fresh data - save ETag and cache response
                etag = response.headers.get("ETag")
                if etag:
                    self.etags[cache_key] = etag
                    self.cached_responses[cache_key] = response.json()
                    print(f"✓ Fresh data: {cache_key}")
                return 200, response.json()

            elif response.status_code == 429:
                # Rate limited - check Retry-After header
                retry_after = response.headers.get("Retry-After")
                print(f"⚠ Rate limited. Retry after {retry_after}s")
                return 429, None

            elif response.status_code == 400:
                # Bad request - log error
                print(f"✗ Bad request: {response.json()}")
                return 400, None

            else:
                print(f"✗ Unexpected status: {response.status_code}")
                return response.status_code, None

        except requests.exceptions.RequestException as e:
            print(f"✗ Request failed: {e}")
            return None, None

# Usage example
client = SprintMetricsClient("http://localhost:3000")

# First request - gets full data with ETag
status1, data1 = client.get_metrics("2026-01-07", "2026-01-21")
print(f"First request: {status1}")  # Output: 200

# Second request - gets 304 Not Modified
status2, data2 = client.get_metrics("2026-01-07", "2026-01-21")
print(f"Second request: {status2}")  # Output: 304
print(f"Data matches: {data2 == data1}")  # Output: True

# Force refresh
status3, data3 = client.get_metrics("2026-01-07", "2026-01-21", force_refresh=True)
print(f"Force refresh: {status3}")  # Output: 200 or 429 (rate limited)
```

### JavaScript: Fetch with ETag

```javascript
class SprintMetricsClient {
    constructor(baseUrl) {
        this.baseUrl = baseUrl;
        this.etags = new Map();
        this.cachedResponses = new Map();
    }

    async getMetrics(startDate, endDate, forceRefresh = false) {
        const url = `${this.baseUrl}/api/sprints/${startDate}/${endDate}/metrics`;
        const cacheKey = `${startDate}:${endDate}`;

        const headers = {};

        // Add ETag from previous response if available
        if (this.etags.has(cacheKey) && !forceRefresh) {
            headers["If-None-Match"] = this.etags.get(cacheKey);
        }

        // Add force_refresh parameter if requested
        const params = new URLSearchParams();
        if (forceRefresh) {
            params.append("force_refresh", "true");
        }
        const queryString = params.toString();
        const fullUrl = queryString ? `${url}?${queryString}` : url;

        try {
            const response = await fetch(fullUrl, {
                headers: headers,
                credentials: "include" // Send cookies for auth
            });

            if (response.status === 304) {
                // Cache hit - return previously cached data
                console.log(`✓ Cache hit: ${cacheKey}`);
                return { status: 304, data: this.cachedResponses.get(cacheKey) };
            }

            if (response.status === 200) {
                // Fresh data - save ETag and cache response
                const data = await response.json();
                const etag = response.headers.get("ETag");
                if (etag) {
                    this.etags.set(cacheKey, etag);
                    this.cachedResponses.set(cacheKey, data);
                }
                console.log(`✓ Fresh data: ${cacheKey}`);
                return { status: 200, data };
            }

            if (response.status === 429) {
                // Rate limited
                const retryAfter = response.headers.get("Retry-After");
                const data = await response.json();
                console.warn(`⚠ Rate limited. Retry after ${retryAfter}s`);
                return { status: 429, data, retryAfter };
            }

            if (response.status === 400) {
                // Bad request
                const data = await response.json();
                console.error(`✗ Bad request: ${data.detail}`);
                return { status: 400, data };
            }

            console.error(`✗ Unexpected status: ${response.status}`);
            return { status: response.status, data: null };
        } catch (error) {
            console.error(`✗ Request failed: ${error.message}`);
            return { status: null, data: null };
        }
    }
}

// Usage example
const client = new SprintMetricsClient("http://localhost:3000");

// First request - gets full data with ETag
const result1 = await client.getMetrics("2026-01-07", "2026-01-21");
console.log(`First request: ${result1.status}`); // Output: 200

// Second request - gets 304 Not Modified
const result2 = await client.getMetrics("2026-01-07", "2026-01-21");
console.log(`Second request: ${result2.status}`); // Output: 304
```

### curl: Manual ETag Testing

```bash
# Save ETag from first response to a file
ETAG_FILE="/tmp/sprint_etag.txt"
RESPONSE_FILE="/tmp/sprint_response.json"

# First request
echo "=== First Request (Get ETag) ==="
curl -i "http://localhost:3000/api/sprints/2026-01-07/2026-01-21/metrics" \
  | tee /tmp/first_response.txt | grep -E "^(HTTP|ETag|Cache-Control)"

# Extract ETag from response headers
ETAG=$(grep "^ETag: " /tmp/first_response.txt | cut -d' ' -f2)
echo "Saved ETag: $ETAG"

# Second request with ETag (should get 304)
echo -e "\n=== Second Request (With ETag - Should Get 304) ==="
curl -i -H "If-None-Match: $ETAG" \
  "http://localhost:3000/api/sprints/2026-01-07/2026-01-21/metrics" \
  | tee /tmp/second_response.txt | grep -E "^(HTTP|ETag|Cache-Control)"

# Force refresh (bypass cache)
echo -e "\n=== Force Refresh (Bypass Cache) ==="
curl -i "http://localhost:3000/api/sprints/2026-01-07/2026-01-21/metrics?force_refresh=true" \
  | grep -E "^(HTTP|ETag|Cache-Control)"
```

---

## Performance Tips

1. **Implement ETag caching** - Reduces bandwidth 99% on repeat requests
2. **Cache responses locally** - Have data ready for 304 responses
3. **Respect rate limits** - Only 5 `force_refresh` per hour per IP
4. **Handle 304 responses** - Check status code before parsing body
5. **Update ETags** - Store new ETag from each response
6. **Check Cache-Control** - Respect `max-age` (default: 5 minutes)

---

## Troubleshooting

### "Invalid date format" Error

Dates must be YYYY-MM-DD format:

```bash
# ✗ Wrong
curl http://localhost:3000/api/sprints/01-07-2026/01-21-2026/metrics

# ✓ Correct
curl http://localhost:3000/api/sprints/2026-01-07/2026-01-21/metrics
```

### "Rate limited" Error

You've exceeded 5 `force_refresh` requests in one hour:

```bash
# Check Retry-After header for when you can retry
curl -H "If-None-Match: ..." http://localhost:3000/api/sprints/2026-01-07/2026-01-21/metrics?force_refresh=true

# Response includes:
# Retry-After: 3600  # Wait 3600 seconds (1 hour)
```

### Getting 200 Instead of 304

Possible reasons:
1. ETag from previous response has expired
2. Data was updated on server (ETag changed)
3. If-None-Match header not sent correctly

**Solution:** Always send the most recent ETag from the previous response.

---

## Support

For issues or questions about agent integration:
- Check CLAUDE.md for OpenDXI architecture overview
- Review TODO files for known issues
- Contact the development team

