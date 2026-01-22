# Refactor GithubService from gh CLI to Direct HTTP

## Overview

Migrate `GithubService` from shelling out to the `gh` CLI to using direct HTTP calls with Faraday. This eliminates the need to install the gh CLI binary in Docker containers, reduces image size by ~50MB, and provides better error handling.

## Problem Statement

The current `GithubService` implementation:
1. **Shells out to `gh` CLI** via `Open3.capture3` (line 207)
2. **Validates gh CLI exists** with `which gh` (line 190)
3. **Parses stderr strings** for error handling (lines 210-216)

This approach:
- Requires installing gh CLI in production Docker images (+50MB)
- Has fragile error handling (parsing stderr strings)
- Adds subprocess overhead for every API call
- Makes testing more complex

## Proposed Solution

Replace subprocess calls with direct HTTP using Faraday:
- Use GitHub GraphQL API endpoint directly (`https://api.github.com/graphql`)
- Authenticate via `Authorization: Bearer <GH_TOKEN>` header
- Handle errors via HTTP status codes and response body
- Fail fast on errors (no retry middleware - this is an internal tool)

## Technical Approach

### Current vs New Architecture

```
CURRENT:
┌─────────────────┐    subprocess    ┌──────────┐    HTTP    ┌────────────┐
│ GithubService   │ ───────────────▶ │ gh CLI   │ ─────────▶ │ GitHub API │
│ (Ruby)          │    Open3         │ (binary) │            │            │
└─────────────────┘                  └──────────┘            └────────────┘

NEW:
┌─────────────────┐         HTTP          ┌────────────┐
│ GithubService   │ ─────────────────────▶│ GitHub API │
│ (Ruby/Faraday)  │  Bearer GH_TOKEN      │            │
└─────────────────┘                       └────────────┘
```

### Design Principles

Based on review feedback from DHH, Kieran, and simplicity analysis:

1. **Keep it simple** - One method for HTTP, not five
2. **Reuse existing exceptions** - Keep the 3 simple exception classes already in the file
3. **No retry middleware** - This is an internal tool; fail fast, let users retry manually
4. **No client memoization** - Faraday connections are cheap; avoids test complexity
5. **Inline test stubs** - Each test documents its own setup

### Implementation

#### Phase 1: Add Faraday Dependency

**1.1 Update Gemfile**

```ruby
# api/Gemfile - Add after rack-cors (line 10)
gem "faraday", "~> 2.0"
```

Note: No `faraday-retry` gem needed. Retry logic is unnecessary for an internal developer tool.

**1.2 Run bundle install**

```bash
cd api && bundle install
```

#### Phase 2: Refactor GithubService

**2.1 Update Exception Classes**

Keep the existing simple exception classes. Only change: delete `GhCliNotFound`.

```ruby
# api/app/services/github_service.rb

class GithubService
  # Keep these existing simple classes (lines 17-19)
  class GitHubApiError < StandardError; end
  class RateLimitExceeded < GitHubApiError; end
  class AuthenticationError < GitHubApiError; end

  # DELETE: GhCliNotFound (no longer needed)
```

**2.2 Add Constant and Replace run_graphql Method**

Replace the entire `run_graphql` method with this simplified version:

```ruby
  GITHUB_GRAPHQL_URL = "https://api.github.com/graphql"

  class << self
    private

    def run_graphql(query, variables)
      token = ENV.fetch("GH_TOKEN") do
        raise GitHubApiError, "GH_TOKEN not set. Create one at https://github.com/settings/tokens"
      end

      response = Faraday.post(GITHUB_GRAPHQL_URL) do |req|
        req.headers["Authorization"] = "Bearer #{token}"
        req.headers["Content-Type"] = "application/json"
        req.body = { query: query, variables: variables }.to_json
      end

      body = JSON.parse(response.body)

      case response.status
      when 200
        if body["errors"] && body["data"].nil?
          raise GitHubApiError, "GraphQL error: #{body['errors'].map { |e| e['message'] }.join('; ')}"
        end
        body
      when 401
        raise AuthenticationError, "GitHub authentication failed. Check GH_TOKEN."
      when 403, 429
        raise RateLimitExceeded, "GitHub API rate limit exceeded"
      else
        raise GitHubApiError, "GitHub API error (#{response.status})"
      end
    rescue Faraday::Error => e
      raise GitHubApiError, "Connection failed: #{e.message}"
    end
```

**2.3 Remove Old Methods**

Delete these methods:
- `validate_gh_cli!` (lines 189-192) - no longer needed

**2.4 Update fetch_sprint_data**

Remove the `validate_gh_cli!` call from line 89. Token validation now happens inline in `run_graphql`.

#### Phase 3: Update Tests

**3.1 Add WebMock for Testing**

```ruby
# api/Gemfile - Add to test group
group :test do
  gem "webmock", "~> 3.0"
end
```

**3.2 Create Unit Tests with Inline Stubs**

```ruby
# api/test/services/github_service_test.rb
require "test_helper"
require "webmock/minitest"

class GithubServiceTest < ActiveSupport::TestCase
  setup do
    @original_token = ENV["GH_TOKEN"]
    @original_org = ENV["GITHUB_ORG"]
    ENV["GH_TOKEN"] = "test-token"
    ENV["GITHUB_ORG"] = "test-org"
  end

  teardown do
    ENV["GH_TOKEN"] = @original_token
    ENV["GITHUB_ORG"] = @original_org
    WebMock.reset!
  end

  test "raises GitHubApiError when GH_TOKEN not set" do
    ENV.delete("GH_TOKEN")

    error = assert_raises(GithubService::GitHubApiError) do
      GithubService.fetch_sprint_data(Date.today - 14, Date.today)
    end

    assert_match(/GH_TOKEN not set/, error.message)
  end

  test "raises AuthenticationError on 401 response" do
    stub_request(:post, "https://api.github.com/graphql")
      .to_return(
        status: 401,
        body: { message: "Bad credentials" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    assert_raises(GithubService::AuthenticationError) do
      GithubService.fetch_sprint_data(Date.today - 14, Date.today)
    end
  end

  test "raises RateLimitExceeded on 429 response" do
    stub_request(:post, "https://api.github.com/graphql")
      .to_return(
        status: 429,
        body: { message: "API rate limit exceeded" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    assert_raises(GithubService::RateLimitExceeded) do
      GithubService.fetch_sprint_data(Date.today - 14, Date.today)
    end
  end

  test "raises RateLimitExceeded on 403 response" do
    stub_request(:post, "https://api.github.com/graphql")
      .to_return(
        status: 403,
        body: { message: "Forbidden" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    assert_raises(GithubService::RateLimitExceeded) do
      GithubService.fetch_sprint_data(Date.today - 14, Date.today)
    end
  end

  test "returns data when no repositories found" do
    stub_request(:post, "https://api.github.com/graphql")
      .to_return(
        status: 200,
        body: {
          data: {
            organization: {
              repositories: {
                pageInfo: { hasNextPage: false, endCursor: nil },
                nodes: []
              }
            }
          }
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = GithubService.fetch_sprint_data(Date.today - 14, Date.today)

    assert_equal [], result["developers"]
    assert_equal 0, result["summary"]["total_commits"]
  end

  test "raises GitHubApiError on GraphQL errors with no data" do
    stub_request(:post, "https://api.github.com/graphql")
      .to_return(
        status: 200,
        body: {
          data: nil,
          errors: [{ message: "Field 'invalid' doesn't exist" }]
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    error = assert_raises(GithubService::GitHubApiError) do
      GithubService.fetch_sprint_data(Date.today - 14, Date.today)
    end

    assert_match(/GraphQL error/, error.message)
  end

  test "handles connection timeout gracefully" do
    stub_request(:post, "https://api.github.com/graphql")
      .to_timeout

    error = assert_raises(GithubService::GitHubApiError) do
      GithubService.fetch_sprint_data(Date.today - 14, Date.today)
    end

    assert_match(/Connection failed/, error.message)
  end

  test "handles unexpected status codes" do
    stub_request(:post, "https://api.github.com/graphql")
      .to_return(
        status: 500,
        body: { message: "Internal Server Error" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    error = assert_raises(GithubService::GitHubApiError) do
      GithubService.fetch_sprint_data(Date.today - 14, Date.today)
    end

    assert_match(/GitHub API error \(500\)/, error.message)
  end
end
```

## Acceptance Criteria

### Functional Requirements

- [x] `GithubService.fetch_sprint_data` works with `GH_TOKEN` env var
- [x] Clear error message when token is missing
- [x] Rate limit errors (403, 429) raise `RateLimitExceeded`
- [x] Authentication errors (401) raise `AuthenticationError`
- [x] GraphQL errors are properly surfaced
- [x] Existing API behavior is preserved

### Non-Functional Requirements

- [x] No `gh` CLI binary required in Docker image
- [x] Simple implementation (~25 lines for HTTP handling)
- [x] Fast failure on errors (no retry delays)

### Quality Gates

- [x] All existing tests pass
- [x] New unit tests for HTTP error scenarios
- [ ] Manual test with real GitHub token
- [ ] Verify in Docker container (no gh CLI installed)

## Files to Create/Modify

| File | Action | Purpose |
|------|--------|---------|
| `api/Gemfile` | Modify | Add faraday, webmock |
| `api/app/services/github_service.rb` | Modify | Replace gh CLI with Faraday HTTP |
| `api/test/services/github_service_test.rb` | Create | Unit tests for HTTP implementation |

## Migration Checklist

### Before Migration

- [x] Ensure `GH_TOKEN` is set in your environment
- [x] Note current behavior with gh CLI for comparison
- [x] Run existing tests to establish baseline

### During Migration

- [x] Add Faraday gem to Gemfile
- [x] Run `bundle install`
- [x] Delete `GhCliNotFound` exception class
- [x] Delete `validate_gh_cli!` method
- [x] Replace `run_graphql` method with simplified version
- [x] Remove `validate_gh_cli!` call from `fetch_sprint_data`
- [x] Add WebMock to test group
- [x] Create unit tests

### After Migration

- [x] Run all tests
- [ ] Manual test: `rails console` → `GithubService.fetch_sprint_data(...)`
- [ ] Test in Docker container without gh CLI
- [ ] Update deployment documentation

## Rollback Plan

If issues arise:
1. Revert changes to `github_service.rb`
2. Remove faraday gem from Gemfile
3. Re-run `bundle install`
4. The gh CLI approach will work again

## GitHub Token Requirements

The `GH_TOKEN` must have these scopes:

| Scope | Purpose |
|-------|---------|
| `repo` | Access private repository data |
| `read:org` | Read organization membership for org-level queries |

**Create token at**: https://github.com/settings/tokens/new

For fine-grained PATs (recommended):
- Repository access: All repositories (or select specific ones)
- Permissions:
  - Contents: Read-only
  - Metadata: Read-only
  - Pull requests: Read-only

## Comparison: Original Plan vs Simplified

| Aspect | Original Plan | Simplified Plan |
|--------|---------------|-----------------|
| Gems added | 2 (`faraday`, `faraday-retry`) | 1 (`faraday`) |
| Exception classes | 4 with rich attributes | 3 simple (existing) |
| Response handler methods | 5 | 1 |
| Lines of new code | ~130 | ~50 |
| Test helper module | Yes (`GithubApiStub`) | No (inline stubs) |
| Client memoization | Yes (causes test issues) | No |
| Retry middleware | Yes | No (fail fast) |

## References

### Internal References
- Current implementation: `api/app/services/github_service.rb`
- Migration recommendation: `api/app/services/github_service.rb:8-9`
- GraphQL queries: `api/app/services/github_service.rb:21-85`

### External References
- [GitHub GraphQL API Docs](https://docs.github.com/en/graphql)
- [GitHub API Rate Limits](https://docs.github.com/en/graphql/overview/rate-limits-and-query-limits-for-the-graphql-api)
- [Faraday Documentation](https://lostisland.github.io/faraday/)
- [WebMock for Testing](https://github.com/bblimke/webmock)
