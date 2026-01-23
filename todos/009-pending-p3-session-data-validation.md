# Add Session Data Validation

**Status:** wontfix
**Priority:** P3 - Nice to Have
**Tags:** security, validation, code-review
**Source:** Data Integrity Guardian

## Problem Statement

Session data from OmniAuth is stored and retrieved without validation. While the session cookie is encrypted and signed, defensive programming suggests validating the data structure.

## Findings

### No Input Sanitization on OAuth Data
**File:** `api/app/controllers/sessions_controller.rb:15-20`

```ruby
user_info = {
  github_id: auth["uid"],
  login: auth["info"]["nickname"],
  name: auth["info"]["name"],  # User-controlled on GitHub
  avatar_url: auth["info"]["image"]
}
session[:user] = user_info
```

### No Session Structure Validation
**File:** `api/app/controllers/api/base_controller.rb:37-39`

```ruby
def current_user
  @current_user ||= session[:user]  # No structure validation
end
```

## Impact

- **XSS Risk:** The `name` field is user-controlled and returned to frontend
- **Data Integrity:** Corrupted session could cause undefined behavior

## Proposed Solution

**Effort:** Small (1 hour)

```ruby
# api/app/controllers/sessions_controller.rb
user_info = {
  github_id: auth["uid"].to_s,
  login: auth.dig("info", "nickname").to_s.downcase.strip,
  name: ActionController::Base.helpers.sanitize(
    auth.dig("info", "name").to_s
  ).truncate(100),
  avatar_url: validate_avatar_url(auth.dig("info", "image"))
}

def validate_avatar_url(url)
  return nil unless url.is_a?(String)
  uri = URI.parse(url) rescue nil
  return nil unless uri && uri.scheme == "https"
  return nil unless uri.host&.end_with?("githubusercontent.com", "github.com")
  url
end
```

```ruby
# api/app/controllers/api/base_controller.rb
def current_user
  return @current_user if defined?(@current_user)

  user = session[:user]
  return nil unless user.is_a?(Hash)
  return nil unless user[:github_id].present? && user[:login].present?

  @current_user = user
end
```

## Acceptance Criteria

- [ ] OAuth data is sanitized before storing in session
- [ ] Session structure is validated on retrieval
- [ ] Avatar URL is validated against trusted hosts
- [ ] Name field is sanitized and truncated

## Work Log

| Date | Action | Notes |
|------|--------|-------|
| 2026-01-23 | Created | Identified during code review |

## Resources

- PR: feat/github-oauth-auth branch
- File: `api/app/controllers/sessions_controller.rb`
- File: `api/app/controllers/api/base_controller.rb`
