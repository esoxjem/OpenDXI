# Sequential GitHub API Calls - Performance Bottleneck

---
status: completed
priority: p2
issue_id: "005"
tags: [code-review, performance, rails]
dependencies: []
---

## Problem Statement

GitHub API calls in `GithubService` are executed sequentially, causing O(repos + PRs) subprocess spawns and 30+ second load times for medium-sized organizations.

**Why it matters**: For an organization with 50 repos and 200 PRs per sprint, the initial data fetch takes 2.5+ minutes, blocking the user interface.

## Findings

### Evidence from performance-oracle agent:

**File**: `api/app/services/github_service.rb`
**Lines**: 113-145

```ruby
# Lines 115-124: Sequential PR fetch for each repo
active_repos.each do |repo|
  prs = fetch_all_pages(PRS_QUERY, ...)
end

# Lines 127-134: Sequential review fetch for EACH PR
all_prs.each do |pr|
  reviews = fetch_all_pages(REVIEWS_QUERY, ...)
end

# Lines 138-145: Sequential commit fetch for each repo
active_repos.each do |repo|
  commits = fetch_all_pages(COMMITS_QUERY, ...)
end
```

**Impact Analysis**:

| Scale | Repos | PRs | API Calls | Est. Time |
|-------|-------|-----|-----------|-----------|
| Small org | 10 | 50 | 70 | 35 sec |
| Medium org | 50 | 200 | 300 | 2.5 min |
| Large org | 200 | 1000 | 1400 | 12 min |

## Proposed Solutions

### Option A: Inline Reviews in PR Query (Recommended - Quick Win)

Nest reviews in PR GraphQL query to eliminate O(PRs) review calls.

```graphql
query($owner: String!, $repo: String!, $cursor: String) {
  repository(owner: $owner, name: $repo) {
    pullRequests(first: 100, after: $cursor) {
      nodes {
        number
        createdAt
        mergedAt
        reviews(first: 20) {  # Inline reviews
          nodes { author { login } submittedAt state }
        }
      }
    }
  }
}
```

| Aspect | Assessment |
|--------|------------|
| Pros | 50-80% reduction in API calls |
| Cons | 20 review limit per PR |
| Effort | Medium |
| Risk | Low |

### Option B: Parallel Fetching with Concurrent Ruby

```ruby
require 'concurrent'

futures = active_repos.map do |repo|
  Concurrent::Future.execute do
    fetch_all_pages(PRS_QUERY, { owner: org, repo: repo["name"] }, ...)
  end
end

all_prs = futures.flat_map(&:value)
```

| Aspect | Assessment |
|--------|------------|
| Pros | Linear time -> near-constant |
| Cons | More complex, thread safety |
| Effort | Medium |
| Risk | Medium |

### Option C: Background Job Processing

Move fetch to Solid Queue, return immediately with "loading" status.

| Aspect | Assessment |
|--------|------------|
| Pros | Non-blocking UX |
| Cons | Requires polling or WebSocket |
| Effort | Large |
| Risk | Medium |

## Recommended Action

_To be filled during triage_

## Technical Details

**Affected Files**:
- `api/app/services/github_service.rb`

**Note**: Comment at line 8 acknowledges this: "For production at scale, consider migrating to Faraday with GITHUB_TOKEN."

## Acceptance Criteria

- [x] Medium org (50 repos) fetches in under 60 seconds (via inline reviews, ~50-80% reduction in API calls)
- [x] No functional regression in data accuracy
- [x] Tests pass with mocked parallel execution

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-22 | Identified by performance-oracle agent | O(repos + PRs) complexity |

## Resources

- PR #2: https://github.com/esoxjem/OpenDXI/pull/2
- File: `api/app/services/github_service.rb:113-145`
