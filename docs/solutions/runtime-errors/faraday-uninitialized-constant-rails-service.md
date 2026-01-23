---
title: "Fix NameError in GithubService - Missing Faraday require statement"
problem_type: runtime_error
severity: high
component:
  - GithubService
  - Backend API
date_solved: 2026-01-22
tags:
  - faraday
  - http-client
  - graphql
  - require
  - gem-integration
  - github-api
  - rails-services
symptoms:
  - "NameError: uninitialized constant Faraday"
  - "LoadError: cannot load such file -- faraday"
  - "500 Internal Server Error on dashboard refresh"
  - "API endpoints fail when triggering GitHub data fetch"
---

# Fix NameError: Uninitialized Constant Faraday in Rails Service

## Problem Statement

After refactoring `GithubService` from `gh` CLI subprocess calls to direct HTTP calls via Faraday, the service threw runtime errors:

```
NameError: uninitialized constant #<Class:GithubService>::Faraday
```

```
LoadError: cannot load such file -- faraday
```

These errors occurred when the dashboard's "Refresh" button triggered GitHub API calls, resulting in 500 Internal Server Error responses. Cached data continued to work, but live API calls failed.

## Investigation Steps

1. **Browser Testing**: Dashboard loaded successfully with cached SQLite data
2. **User Action Testing**: Clicking "Refresh" consistently triggered 500 errors
3. **Rails Logs Analysis**: Found `NameError: uninitialized constant Faraday`
4. **Gemfile Verification**: Confirmed `gem "faraday", "~> 2.0"` was declared
5. **Gemfile.lock Check**: Verified Faraday 2.14.0 was properly resolved
6. **Manual Require Test**: `bundle exec ruby -e "require 'faraday'"` succeeded
7. **Service File Review**: Discovered missing `require` statement at file top

## Root Cause Analysis

**Rails autoloading behavior**:
- Rails' Zeitwerk autoloader only loads classes from `app/` directories
- External gems (from `vendor/bundle/`) require explicit `require` statements
- Bundler makes gems *available* but doesn't auto-require them

**Why the Gemfile entry wasn't enough**:
- The Gemfile declares dependencies but doesn't automatically load them in every file
- Each file must explicitly require the gems it uses
- Without `require "faraday"`, Ruby cannot find the Faraday constant

## Working Solution

Add `require "faraday"` at the top of the service file:

**File**: `api/app/services/github_service.rb`

```ruby
# frozen_string_literal: true

require "faraday"

# GitHub GraphQL API Service
class GithubService
  # ... implementation
end
```

Then restart the Rails server to pick up the bundled gem in the new process context.

## Verification

After applying the fix and restarting:

1. **API Health Check**: `curl http://localhost:3000/api/health` returns `{"status":"ok"}`

2. **Rails Logs**: Successful GitHub API calls:
   ```
   [GithubService] Fetching sprint 2026-01-21 to 2026-02-03 for org: ShareTheMeal
   [GithubService]   Step 1: Fetching repositories... Found 38 total
   [GithubService]   Step 2: 5 repos with activity in sprint window
   [GithubService]   Step 3: Fetching PRs... Found 24 total PRs
   [GithubService]   Step 4: Fetching commits... Found 23 total commits
   [GithubService]   Step 5: Aggregating data...
   [GithubService]   Done! 14 developers, 14 daily entries
   Completed 200 OK
   ```

3. **Dashboard Updates**: Fresh data appears after clicking Refresh

## Prevention Strategies

### Checklist When Adding New Gem Dependencies

1. [ ] Add gem to `Gemfile` with version constraint
2. [ ] Run `bundle install`
3. [ ] Add `require` statement at top of service file
4. [ ] Restart Rails server
5. [ ] Test the specific code path that uses the gem

### Alternative Approaches

| Approach | Pros | Cons |
|----------|------|------|
| **Explicit require in service** (recommended) | Clear dependency, fails fast | Must remember for each file |
| **Require in initializer** | Single location, centralized | Less explicit, initializer grows |
| **`require: true` in Gemfile** | Never forget | Slower boot, less visibility |

### Test Case to Catch This Early

```ruby
# test/services/github_service_test.rb
class GithubServiceTest < ActiveSupport::TestCase
  test "service can be instantiated without errors" do
    # This exercises the require at class load time
    assert_kind_of Class, GithubService
  end

  test "fetch_sprint_data uses Faraday for HTTP requests" do
    stub_request(:post, "https://api.github.com/graphql")
      .to_return(status: 401, body: "Bad credentials")

    assert_raises(GithubService::AuthenticationError) do
      GithubService.fetch_sprint_data(Date.today - 14, Date.today)
    end
  end
end
```

### Code Review Checklist Item

When reviewing PRs that add gem dependencies:

- [ ] Gem added to `Gemfile` with version constraint
- [ ] `Gemfile.lock` updated
- [ ] `require` statement added to files using the gem
- [ ] Tests exercise the code path using the gem
- [ ] Server restart noted in PR description if applicable

## Key Takeaway

**Explicit requires are essential for external gems, even when declared in the Gemfile.** Rails' sophisticated autoloading handles application code, but external dependencies must be explicitly required in the files that use them.

## Related

- [Faraday gem documentation](https://lostisland.github.io/faraday/)
- [Zeitwerk autoloading guide](https://guides.rubyonrails.org/autoloading_and_reloading_constants.html)
- Branch: `feat/github-service-http`
