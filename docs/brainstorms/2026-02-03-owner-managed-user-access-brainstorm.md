# Brainstorm: Owner-Managed User Access

**Date:** 2026-02-03
**Status:** Ready for planning

## What We're Building

A user management system where **owners can add team members by GitHub handle** through the Settings UI, replacing the current env var-based access control.

### Current State
- `GITHUB_ALLOWED_USERS` env var controls who can log in (requires redeploy to change)
- Users are created passively when they complete OAuth login
- Owners can only manage roles of users who have already logged in
- Settings page shows "no users found" until someone logs in

### Target State
- Owners add users by GitHub handle directly in the Settings UI
- User records are pre-created immediately (fetching details from GitHub API)
- New users appear in the list right away, before they've logged in
- When users log in via OAuth, they're matched to their existing record
- Database is the single source of truth for access control

## Why This Approach

**Pre-creating user records (vs. allow-list only):**
- Better UX: owners see who has access immediately
- Enables role assignment before first login
- Cleaner data model: one User table, no separate "pending" or "invited" states
- GitHub API provides all needed data (github_id, name, avatar_url)

**Hard delete (vs. soft delete):**
- Simpler implementation and mental model
- No "inactive" states to manage or explain
- If someone needs to be re-added, it's a fresh start
- Matches the simplicity of the current env var approach

**Keeping bootstrap env var:**
- Solves chicken-and-egg: how does the first owner get created?
- One-time use: only matters when database has no owners
- Familiar pattern for self-hosted apps
- Alternative (CLI seed) requires command-line access

## Key Decisions

1. **Add user flow:**
   - Owner enters GitHub handle in Settings UI
   - Backend calls GitHub API to fetch user details
   - Creates User record with `role: developer` (default)
   - User appears in list immediately

2. **Login flow (updated):**
   - User initiates GitHub OAuth
   - On callback, lookup user by `github_id`
   - If found → authenticate and create session
   - If not found → reject login (not authorized)

3. **Remove user flow:**
   - Owner clicks remove/delete on a user
   - User record is hard deleted from database
   - If user tries to log in → rejected (no matching record)

4. **Bootstrap flow (unchanged):**
   - `OWNER_GITHUB_USERNAME` env var checked on OAuth callback
   - If user's login matches AND no owners exist → create as owner
   - Otherwise, standard login flow applies

5. **Env var cleanup:**
   - Remove `GITHUB_ALLOWED_USERS` env var entirely
   - Remove related code in `SessionsController` and `BaseController`
   - Update documentation

## API Changes

### New Endpoint: Create User
```
POST /api/users
Body: { "login": "alice" }
Response: { "user": { id, github_id, login, name, avatar_url, role } }
Errors:
  - 404 if GitHub user not found
  - 409 if user already exists
  - 403 if not owner
```

### New Endpoint: Delete User
```
DELETE /api/users/:id
Response: { "success": true }
Errors:
  - 404 if user not found
  - 403 if not owner
  - 422 if trying to delete yourself (prevent lockout)
```

### Existing Endpoints (unchanged)
- `GET /api/users` - list all users
- `PATCH /api/users/:id` - update role

## UI Changes

### Settings Page
- Add "Add User" button/form
- Input field for GitHub handle
- Loading state while fetching from GitHub API
- Error handling (user not found, already exists)
- Add delete button to each user row
- Confirmation dialog before delete
- Prevent self-deletion

## Open Questions

1. **Should owners be able to delete other owners?**
   - Risk: could lead to no owners remaining
   - Option: prevent if it would leave zero owners

2. **What if GitHub handle changes?**
   - GitHub allows username changes
   - We match by `github_id` (immutable), so this should be fine
   - Could update `login` on next OAuth login

3. **Rate limiting on GitHub API?**
   - Fetching user details is lightweight
   - Probably fine for small teams
   - Could add caching if needed

## Out of Scope

- Email notifications/invitations
- Invite links or tokens
- "Pending" user states
- Bulk user import
- User self-registration

## Next Steps

Run `/workflows:plan` to create implementation plan.
