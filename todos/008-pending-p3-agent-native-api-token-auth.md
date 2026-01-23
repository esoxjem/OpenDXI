# Add API Token Authentication for Agents

**Status:** wontfix
**Priority:** P3 - Nice to Have
**Tags:** architecture, agent-native, authentication, code-review
**Source:** Agent-Native Reviewer

## Problem Statement

The authentication system is designed entirely for browser-based human users. Automated agents, CI/CD pipelines, and programmatic clients cannot authenticate because OAuth requires browser interaction.

## Findings

### No Agent Authentication Path
**File:** `api/app/controllers/api/base_controller.rb:27-35`

```ruby
def authenticate!
  return if current_user
  render json: {
    error: "unauthorized",
    detail: "Please log in to access this resource",
    login_url: "/auth/github"  # Browser-only!
  }, status: :unauthorized
end

def current_user
  @current_user ||= session[:user]  # Session = browser cookies only
end
```

### Capability Map

| Action | User | Agent |
|--------|------|-------|
| Sign in | OAuth (browser) | **BLOCKED** |
| Check auth status | Works | **BLOCKED** |
| Access API | Works | **BLOCKED** |
| Logout | Works | N/A |

## Impact

- **Automation:** No CI/CD integration possible
- **Agents:** Claude Code and other AI agents cannot authenticate
- **Scripts:** No programmatic access for data export/import

## Proposed Solution

**Effort:** Large (4-6 hours)

### 1. Create ApiToken Model

```ruby
# db/migrate/xxx_create_api_tokens.rb
class CreateApiTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :api_tokens do |t|
      t.string :token_digest, null: false, index: { unique: true }
      t.json :user_info, null: false
      t.string :name
      t.datetime :expires_at
      t.datetime :last_used_at
      t.timestamps
    end
  end
end
```

### 2. Extend Authentication

```ruby
# api/app/controllers/api/base_controller.rb
def current_user
  @current_user ||= session[:user] || authenticate_via_api_token
end

def authenticate_via_api_token
  token = request.headers["Authorization"]&.remove("Bearer ")
  return nil unless token

  api_token = ApiToken.find_by_token(token)
  return nil unless api_token&.valid?

  api_token.touch(:last_used_at)
  api_token.user_info
end
```

### 3. Add Token Management Endpoints

```ruby
# POST /api/auth/tokens - Create token (requires OAuth session)
# GET /api/auth/tokens - List tokens
# DELETE /api/auth/tokens/:id - Revoke token
```

## Acceptance Criteria

- [ ] Users can create API tokens via web UI
- [ ] API accepts `Authorization: Bearer <token>` header
- [ ] Tokens can be revoked
- [ ] Tokens have configurable expiration
- [ ] `/api/auth/me` shows available auth methods

## Work Log

| Date | Action | Notes |
|------|--------|-------|
| 2026-01-23 | Created | Identified during code review |

## Resources

- PR: feat/github-oauth-auth branch
- Agent-Native Architecture principles
