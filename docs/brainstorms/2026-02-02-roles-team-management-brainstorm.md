# Brainstorm: Roles & Team Management

**Date:** 2026-02-02
**Status:** Ready for planning
**Branch:** `roles-team-management`

---

## What We're Building

A role-based access control (RBAC) foundation for OpenDXI with two org-level roles:

| Role | Description | Capabilities |
|------|-------------|--------------|
| **Owner** | Org administrator | Access settings, manage users, assign roles |
| **Developer** | Regular user | View dashboard metrics |

> **Note:** Manager role deferred until there are actual Manager-specific permissions to implement. See [Review Feedback](#review-feedback) for rationale.

### Scope of This Iteration

**In scope:**
- `User` model with `role` enum (owner/developer)
- Persist users to database on first OAuth login
- Settings page accessible only to Owners
- User management UI (view users, assign roles)
- Bootstrap first Owner via `OWNER_GITHUB_USERNAME` env var

**Out of scope (future iterations):**
- Manager role and permissions
- Teams and team membership
- Team-specific metrics/views
- Multi-tenant (multiple GitHub orgs)

---

## Why This Approach

### Decision: Minimal RBAC First, Teams Later

We chose to implement roles without teams because:

1. **Foundation first** - Roles are prerequisite for any permission system
2. **Avoid premature complexity** - Team features aren't fully defined yet
3. **Faster feedback loop** - Ship roles, learn from usage, then design teams
4. **YAGNI** - Only build what we need now (two roles, not three)

### Alternatives Considered

| Approach | Why Not |
|----------|---------|
| Roles + Teams together | Larger scope, may build unused features |
| Three roles (with Manager) | Manager has no distinct permissions yet — pure YAGNI violation |
| Soft roles (env vars only) | Doesn't scale, can't support future team membership |

---

## Key Decisions

### 1. User Persistence

**Decision:** Persist users to SQLite on first OAuth login.

**Current state:** Users exist only in session (not stored in DB).

**Change:** Create `User` model, upsert on OAuth callback.

```ruby
# Migration
create_table :users do |t|
  t.bigint :github_id, null: false
  t.string :login, null: false
  t.string :name                      # Can be null (some GitHub users don't set it)
  t.string :avatar_url, null: false
  t.integer :role, null: false, default: 0
  t.timestamps
end

add_index :users, :github_id, unique: true
add_index :users, :login, unique: true
```

### 2. Role Hierarchy

**Decision:** Two org-level roles (not team-level).

```
Owner (org admin)
  └── Developer (view metrics)
```

All roles are org-wide. Team-scoped roles come later with Team model. Manager role added when there's something for Managers to manage.

### 3. First Owner Bootstrap

**Decision:** Environment variable `OWNER_GITHUB_USERNAME`.

- Matches existing config pattern (`GITHUB_ALLOWED_USERS`, `GITHUB_ORG`)
- Explicit and auditable
- User with matching GitHub login gets `owner` role on first login
- **Case-insensitive comparison** (GitHub usernames are case-insensitive)
- Other users default to `developer` role

```ruby
# In User model
def self.owner_bootstrap_login?(login)
  ENV["OWNER_GITHUB_USERNAME"]&.downcase == login&.downcase
end
```

### 4. Settings UI Location

**Decision:** Avatar dropdown menu → "Settings"

- Clean separation from main dashboard
- Common UX pattern for admin/settings
- Visible only to Owners (hide menu item for other roles)

> **Changed from "Org Settings"** — there's no Org model in a single-tenant app. Just call it "Settings".

### 5. Single-Tenant

**Decision:** Stay single-tenant (one GitHub org per deployment).

- Simpler data model (no org scoping on queries)
- Matches current architecture
- Multi-tenant can be added later if needed

### 6. Authorization Approach

**Decision:** Simple `before_action` callback, not a gem.

For two roles with one protected page, Pundit/CanCanCan are overkill:

```ruby
# app/controllers/settings_controller.rb
class SettingsController < ApplicationController
  before_action :require_owner!

  private

  def require_owner!
    head :forbidden unless current_user&.owner?
  end
end
```

Revisit if authorization logic grows to 5+ policies.

---

## Data Model

```
┌─────────────────────────────┐
│           User              │
├─────────────────────────────┤
│ id: bigint (PK)             │
│ github_id: bigint (unique)  │  ← NOT string (GitHub IDs are integers)
│ login: string (unique)      │  ← Unique index added
│ name: string (nullable)     │
│ avatar_url: string          │
│ role: integer               │  ← Explicit enum mapping
│ created_at: datetime        │
│ updated_at: datetime        │
└─────────────────────────────┘

# Explicit enum mapping (defensive coding)
enum :role, { developer: 0, owner: 1 }, default: :developer
```

**Future expansion (not this iteration):**

```
┌──────────────┐       ┌─────────────────┐       ┌──────────────┐
│    User      │──────<│ TeamMembership  │>──────│    Team      │
└──────────────┘       └─────────────────┘       └──────────────┘

# Manager role added when Teams are implemented
enum :role, { developer: 0, manager: 1, owner: 2 }
```

---

## Implementation Notes

### OAuth Callback Changes

Extract user creation logic to model method for testability:

```ruby
# app/models/user.rb
class User < ApplicationRecord
  enum :role, { developer: 0, owner: 1 }, default: :developer

  def self.find_or_create_from_github(auth_hash)
    user = find_or_initialize_by(github_id: auth_hash.uid)

    user.assign_attributes(
      login: auth_hash.info.nickname,
      name: auth_hash.info.name,
      avatar_url: auth_hash.info.image
    )

    user.role = :owner if user.new_record? && owner_bootstrap_login?(user.login)
    user.save!
    user
  end

  def self.owner_bootstrap_login?(login)
    ENV["OWNER_GITHUB_USERNAME"]&.downcase == login&.downcase
  end
end
```

### Session Changes

Store `user_id` instead of full auth hash:

```ruby
# Before (current)
session[:github_user] = auth_hash

# After
session[:user_id] = user.id

# current_user helper
def current_user
  @current_user ||= User.find_by(id: session[:user_id])
end
```

### Controller Structure

Use namespaced controller for future expansion:

```ruby
# config/routes.rb
namespace :settings do
  resources :users, only: [:index, :update]
end

# app/controllers/settings/users_controller.rb
module Settings
  class UsersController < ApplicationController
    before_action :require_owner!

    def index
      @users = User.order(:login)
    end

    def update
      @user = User.find(params[:id])
      @user.update!(role: params[:role])
      redirect_to settings_users_path, notice: "Role updated"
    end
  end
end
```

---

## UI/UX Sketch

### Avatar Dropdown (all users)
```
┌─────────────────────┐
│ [Avatar] Username   │
├─────────────────────┤
│ Settings*           │  ← Only visible to Owners
├─────────────────────┤
│ Sign Out            │
└─────────────────────┘
```

### Settings Page (Owners only)
```
┌─────────────────────────────────────────────────┐
│ Settings                                        │
├─────────────────────────────────────────────────┤
│                                                 │
│ Users                                           │
│ ┌─────────────────────────────────────────────┐ │
│ │ [Avatar] alice    Owner     ▼              │ │
│ │ [Avatar] bob      Developer ▼              │ │
│ │ [Avatar] carol    Developer ▼              │ │
│ └─────────────────────────────────────────────┘ │
│                                                 │
│ (Teams section - future iteration)              │
│                                                 │
└─────────────────────────────────────────────────┘
```

---

## Resolved Questions

| Question | Resolution |
|----------|------------|
| Owner deleted/renamed on GitHub? | **Ignore for now.** Handle when it actually happens. The env var only affects first login. |
| Can an Owner demote themselves? | **Yes, allow it.** Add "last owner" protection only if someone actually does this by accident. |
| Should Managers see settings read-only? | **N/A.** Manager role deferred. |
| Users in ALLOWED_USERS who haven't logged in? | **Don't show them.** Users don't exist until they login. Zero code needed. |

---

## Success Criteria

- [ ] Users are persisted to database with role (developer/owner)
- [ ] Owner can access `/settings/users`
- [ ] Owner can change other users' roles
- [ ] Non-owners cannot access settings (403 or hidden link)
- [ ] First owner is bootstrapped from `OWNER_GITHUB_USERNAME` env var
- [ ] Existing OAuth flow continues to work
- [ ] `current_user` returns a `User` model instance (not a hash)

---

## Review Feedback

This plan was reviewed by three specialized agents on 2026-02-02:

### DHH Rails Reviewer (Score: 7/10)
- ✅ Approved YAGNI approach, single-tenant decision, env var bootstrap
- 🔴 **Remove Manager role** — "You are adding a column value that does nothing"
- 🔴 **Rename to "Settings"** — "Do not name things after abstractions that do not exist"
- ⚠️ Avoid authorization gems for two roles

### Kieran Rails Reviewer (Pass with changes)
- ✅ Sound scope and architecture
- 🔴 **Fix `github_id` to `bigint`** — GitHub IDs are integers, not strings
- 🔴 **Use explicit enum mapping** — never rely on implicit array ordering
- 🔴 **Add unique index on `login`** — GitHub usernames are unique
- ⚠️ Extract bootstrap logic to model method for testability
- ⚠️ Case-insensitive username comparison

### Code Simplicity Reviewer (~30% LOC reduction)
- 🔴 **Remove Manager role** — pure YAGNI violation
- 🔴 **Delete open questions** — edge cases to handle when they occur
- ⚠️ Consider slimmer schema (name/avatar_url optional)
- ✅ Core idea is sound: persist users, owner role, gate settings

### Changes Made Based on Feedback

1. ✅ Removed Manager role from this iteration
2. ✅ Changed `github_id` from string to bigint
3. ✅ Added unique index on `login`
4. ✅ Added explicit enum integer mapping
5. ✅ Renamed "Org Settings" to "Settings"
6. ✅ Added case-insensitive username comparison
7. ✅ Resolved all open questions
8. ✅ Added implementation notes with model extraction
9. ✅ Documented authorization approach decision

---

## Next Steps

Run `/workflows:plan` to create implementation plan.
