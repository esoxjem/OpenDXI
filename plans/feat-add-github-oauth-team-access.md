# feat: Add GitHub OAuth with Team-Based Access Control

## Review Summary

> **Plan reviewed by:** DHH Rails Reviewer, Kieran Rails Reviewer, Code Simplicity Reviewer
> **Date:** 2026-01-23
> **Status:** Revised based on feedback

### Key Changes from Review

| Original | Revised | Rationale |
|----------|---------|-----------|
| Separate `GithubTeamVerifier` service | Add methods to existing `GithubService` | "Java programmer's approach" - DHH |
| React Context `AuthProvider` | TanStack Query `useAuth()` hook | Uses existing infrastructure, -50 LOC |
| Next.js route middleware | Removed entirely | Can't validate session client-side |
| Store OAuth token in session | Discard after verification | Security risk, never used after login |
| `respond_to do \|format\|` blocks | Direct `render json:` | API-only app, always JSON |
| CSRF protection on API | Removed | CORS with explicit origins is sufficient |
| `module Api` namespacing | `class Api::ClassName` pattern | Rails convention |

### Files Removed from Plan

- ~~`api/app/services/github_team_verifier.rb`~~ → Methods added to `GithubService`
- ~~`frontend/src/contexts/AuthContext.tsx`~~ → Replaced with `useAuth()` hook
- ~~`frontend/src/middleware.ts`~~ → Removed (security theater)

---

## Overview

Add GitHub OAuth authentication to prevent publicly exposing the OpenDXI dashboard on deployment. Only members of specific GitHub teams within the organization can access the application.

**Architecture Decision:** Rails backend handles OAuth flow, session management, and team verification. Next.js frontend checks authentication status via Rails API and redirects unauthenticated users to login.

## Problem Statement

Currently, the OpenDXI dashboard has **zero authentication** - all endpoints are publicly accessible:
- Anyone can view developer productivity metrics
- Sensitive team performance data is exposed
- No way to restrict access to authorized personnel only

This is unacceptable for production deployment where metrics may contain confidential information about team performance.

## Proposed Solution

Implement GitHub OAuth with team-based authorization:

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Next.js       │     │   Rails API     │     │   GitHub        │
│   Frontend      │────▶│   Backend       │────▶│   OAuth + API   │
│                 │     │                 │     │                 │
│ • Auth check    │     │ • OAuth flow    │     │ • User auth     │
│ • Protected     │     │ • Session mgmt  │     │ • Team verify   │
│   routes        │     │ • Team verify   │     │                 │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

### Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Auth Library | OmniAuth (no Devise) | Simpler, focused, DHH-approved (~150 lines vs thousands) |
| Session Storage | Encrypted cookies | No database changes, survives deploys, Coolify-friendly |
| Team Verification | At login only (MVP) | Simpler implementation, can add periodic re-check later |
| Cookie Strategy | `SameSite=None; Secure` | Required for cross-origin (different subdomains) |

## Technical Approach

### Phase 1: Backend OAuth Infrastructure

#### 1.1 Add Required Gems

**File:** `api/Gemfile`

```ruby
# Authentication
gem "omniauth", "~> 2.1"
gem "omniauth-github", "~> 2.0"
gem "omniauth-rails_csrf_protection"
```

#### 1.2 Re-enable Session Middleware

**File:** `api/config/application.rb`

```ruby
module OpendxiRails
  class Application < Rails::Application
    config.load_defaults 8.1
    config.api_only = true

    # Re-add session middleware for OAuth (required for API-only mode)
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore,
      key: "_opendxi_session",
      same_site: :none,        # Required for cross-origin cookies
      secure: Rails.env.production?
  end
end
```

#### 1.3 Configure OmniAuth

**File:** `api/config/initializers/omniauth.rb` (create)

```ruby
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :github,
    ENV.fetch("GITHUB_OAUTH_CLIENT_ID"),
    ENV.fetch("GITHUB_OAUTH_CLIENT_SECRET"),
    scope: "read:user,read:org",
    callback_url: ENV.fetch("GITHUB_OAUTH_CALLBACK_URL", nil)
end

OmniAuth.config.logger = Rails.logger
OmniAuth.config.allowed_request_methods = [:post]  # Security: POST only
OmniAuth.config.silence_get_warning = true
```

#### 1.4 Update CORS Configuration

**File:** `api/config/initializers/cors.rb`

> **Review note:** Must include both `/api/*` and `/auth/*` routes for OAuth to work cross-origin.

```ruby
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*ENV.fetch("CORS_ORIGINS", "http://localhost:3001").split(",").map(&:strip))

    # OAuth routes (cross-origin form submission)
    resource "/auth/*",
      headers: :any,
      methods: %i[get post options],
      credentials: true

    # API routes
    resource "/api/*",
      headers: :any,
      methods: %i[get post put patch delete options head],
      credentials: true,
      max_age: 86400
  end
end
```

#### 1.5 Add OAuth Routes

**File:** `api/config/routes.rb`

```ruby
Rails.application.routes.draw do
  # Health check (PUBLIC - no auth required)
  get "up" => "rails/health#show", as: :rails_health_check

  # OAuth routes (PUBLIC - handles auth flow)
  # Note: POST /auth/github is handled by OmniAuth middleware automatically
  get "/auth/github/callback", to: "sessions#create"
  get "/auth/failure", to: "sessions#failure"
  delete "/auth/logout", to: "sessions#destroy"

  namespace :api do
    # Auth status endpoint
    get "auth/me", to: "auth#me"

    # Protected endpoints (existing)
    get "health", to: "health#show"
    get "config", to: "config#show"
    resources :sprints, only: [:index] do
      collection do
        get "history"
        get ":start_date/:end_date/metrics", to: "sprints#metrics", as: :metrics
      end
    end
    resources :developers, only: [:index] do
      member do
        get "history"
      end
    end
  end
end
```

#### 1.6 Create Sessions Controller

**File:** `api/app/controllers/sessions_controller.rb` (create)

> **Review note:** OAuth token is used for team verification only, then discarded (not stored in session). Logout moved here from separate AuthController.

```ruby
class SessionsController < ApplicationController
  def create
    auth = request.env["omniauth.auth"]
    access_token = auth["credentials"]["token"]

    user_info = {
      github_id: auth["uid"],
      login: auth["info"]["nickname"],
      name: auth["info"]["name"],
      avatar_url: auth["info"]["image"]
    }

    # Verify team membership using token, then discard token
    unless authorized_team_member?(access_token, user_info[:login])
      redirect_to failure_url("not_in_team"), allow_other_host: true
      return
    end

    # Create session (token NOT stored - security best practice)
    session[:user] = user_info
    session[:authenticated_at] = Time.current.iso8601

    redirect_to frontend_url, allow_other_host: true
  end

  def destroy
    reset_session
    redirect_to "#{frontend_url}/login", allow_other_host: true
  end

  def failure
    error = params[:message] || "unknown_error"
    redirect_to failure_url(error), allow_other_host: true
  end

  private

  def authorized_team_member?(access_token, username)
    allowed_teams = Rails.application.config.opendxi.allowed_teams
    return true if allowed_teams.empty?

    org = Rails.application.config.opendxi.github_org
    return false unless org

    GithubService.user_in_any_team?(
      access_token: access_token,
      org: org,
      team_slugs: allowed_teams,
      username: username
    )
  end

  def frontend_url
    ENV.fetch("FRONTEND_URL", "http://localhost:3001")
  end

  def failure_url(error)
    "#{frontend_url}/login?error=#{error}"
  end
end
```

#### 1.7 Create Auth API Controller

**File:** `api/app/controllers/api/auth_controller.rb` (create)

> **Review note:** Uses `class Api::ClassName` namespacing pattern. Logout moved to SessionsController. This controller only returns auth status.

```ruby
class Api::AuthController < Api::BaseController
  skip_before_action :authenticate!, only: [:me]

  def me
    if current_user
      render json: { authenticated: true, user: current_user }
    else
      render json: { authenticated: false, login_url: "/auth/github" }, status: :unauthorized
    end
  end
end
```

#### 1.8 Add Team Verification to Existing GithubService

**File:** `api/app/services/github_service.rb` (modify - add class methods)

> **Review note:** Instead of creating a separate `GithubTeamVerifier` service class, add class methods to the existing `GithubService`. This keeps related GitHub API code together and avoids unnecessary abstraction.

```ruby
class GithubService
  # ... existing instance methods ...

  # Class methods for OAuth team verification (uses user's OAuth token, not GH_TOKEN)
  def self.user_in_team?(access_token:, org:, team_slug:, username:)
    response = Faraday.get("https://api.github.com/orgs/#{org}/teams/#{team_slug}/memberships/#{username}") do |req|
      req.headers["Authorization"] = "Bearer #{access_token}"
      req.headers["Accept"] = "application/vnd.github+json"
      req.headers["X-GitHub-Api-Version"] = "2022-11-28"
    end

    response.status == 200 && JSON.parse(response.body)["state"] == "active"
  rescue Faraday::Error, JSON::ParserError => e
    Rails.logger.error("[GithubService] Team verification failed: #{e.message}")
    false
  end

  def self.user_in_any_team?(access_token:, org:, team_slugs:, username:)
    team_slugs.any? do |slug|
      user_in_team?(access_token: access_token, org: org, team_slug: slug, username: username)
    end
  end
end
```

#### 1.9 Update Base Controller with Authentication

**File:** `api/app/controllers/api/base_controller.rb`

> **Review note:** Uses `class Api::BaseController` pattern. Removed `respond_to` block - this is a JSON-only API. Added cookies support for session access.

```ruby
class Api::BaseController < ActionController::API
  include ActionController::Cookies

  before_action :authenticate!

  private

  def authenticate!
    return if current_user

    render json: {
      error: "unauthorized",
      detail: "Please log in to access this resource",
      login_url: "/auth/github"
    }, status: :unauthorized
  end

  def current_user
    @current_user ||= session[:user]
  end
end
```

#### 1.10 Application Controller (No Changes Needed)

**File:** `api/app/controllers/application_controller.rb`

> **Review note:** Keep existing `ApplicationController` as `ActionController::Base`. The `SessionsController` inherits from this for browser-based OAuth callbacks. CSRF protection is NOT needed - CORS with explicit origins and `credentials: true` is sufficient protection for cross-origin requests. The `omniauth-rails_csrf_protection` gem handles CSRF for the OAuth flow specifically.

```ruby
# No changes - keep existing ApplicationController
class ApplicationController < ActionController::Base
  allow_browser versions: :modern, only: :health_check
end
```

#### 1.11 Update Configuration Initializer

**File:** `api/config/initializers/opendxi.rb`

```ruby
Rails.application.configure do
  config.opendxi = ActiveSupport::OrderedOptions.new
  config.opendxi.github_org = ENV.fetch("GITHUB_ORG", nil)
  config.opendxi.sprint_start_date = Date.parse(ENV.fetch("SPRINT_START_DATE", "2026-01-07"))
  config.opendxi.sprint_duration_days = ENV.fetch("SPRINT_DURATION_DAYS", "14").to_i
  config.opendxi.max_pages_per_query = ENV.fetch("MAX_PAGES_PER_QUERY", "10").to_i

  # OAuth configuration
  config.opendxi.allowed_teams = ENV.fetch("GITHUB_ALLOWED_TEAMS", "").split(",").map(&:strip).reject(&:empty?)
end
```

#### 1.12 Add Environment Variables

**File:** `api/.env.example` (update)

```bash
# Existing variables...
GITHUB_ORG=your-organization
GH_TOKEN=ghp_your_personal_access_token

# NEW: GitHub OAuth App credentials
GITHUB_OAUTH_CLIENT_ID=your_oauth_client_id
GITHUB_OAUTH_CLIENT_SECRET=your_oauth_client_secret
GITHUB_OAUTH_CALLBACK_URL=http://localhost:3000/auth/github/callback

# NEW: Team-based authorization (comma-separated team slugs)
GITHUB_ALLOWED_TEAMS=engineering,devops

# NEW: Frontend URL for redirects
FRONTEND_URL=http://localhost:3001

# Updated: CORS must include credentials
CORS_ORIGINS=http://localhost:3001
```

### Phase 2: Frontend Authentication Integration

#### 2.1 Update API Client

**File:** `frontend/src/lib/api.ts`

```typescript
const API_URL = process.env.NEXT_PUBLIC_API_URL || "http://localhost:3000";

interface ApiError {
  error: string;
  message: string;
  login_url?: string;
}

export async function apiRequest<T>(
  endpoint: string,
  options: RequestInit = {}
): Promise<T> {
  const response = await fetch(`${API_URL}${endpoint}`, {
    ...options,
    credentials: "include", // CRITICAL: Send cookies cross-origin
    headers: {
      "Content-Type": "application/json",
      ...options.headers,
    },
  });

  if (!response.ok) {
    if (response.status === 401) {
      // Redirect to login on auth failure
      const data = (await response.json()) as ApiError;
      if (typeof window !== "undefined") {
        window.location.href = "/login";
      }
      throw new Error(data.message || "Unauthorized");
    }
    throw new Error(`API error: ${response.status}`);
  }

  return response.json();
}

// Auth-specific functions
export interface AuthStatus {
  authenticated: boolean;
  user?: {
    github_id: number;
    login: string;
    name: string;
    avatar_url: string;
  };
  login_url?: string;
}

export async function checkAuthStatus(): Promise<AuthStatus> {
  const response = await fetch(`${API_URL}/api/auth/me`, {
    credentials: "include",
  });
  return response.json();
}

export async function logout(): Promise<void> {
  await fetch(`${API_URL}/api/auth/logout`, {
    method: "DELETE",
    credentials: "include",
  });
}
```

#### 2.2 Create Auth Hook (Using TanStack Query)

**File:** `frontend/src/hooks/useAuth.ts` (create)

> **Review note:** Uses TanStack Query instead of React Context. This follows the existing pattern in the codebase (see `useMetrics.ts`) and eliminates ~50 lines of boilerplate. No `AuthProvider` needed.

```tsx
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { checkAuthStatus, logout as apiLogout, AuthStatus } from "@/lib/api";

export function useAuth() {
  const queryClient = useQueryClient();

  const { data, isLoading, error } = useQuery({
    queryKey: ["auth"],
    queryFn: checkAuthStatus,
    retry: false,
    staleTime: 5 * 60 * 1000, // 5 minutes
  });

  const logout = async () => {
    await apiLogout();
    queryClient.setQueryData(["auth"], { authenticated: false });
    window.location.href = "/login";
  };

  return {
    user: data?.user ?? null,
    isLoading,
    isAuthenticated: data?.authenticated ?? false,
    error: error instanceof Error ? error.message : null,
    logout,
  };
}
```

#### 2.3 Update Providers (Minimal Changes)

**File:** `frontend/src/app/providers.tsx`

> **Review note:** No `AuthProvider` needed - `useAuth` hook uses TanStack Query directly. Only change is adding retry logic for auth errors.

```tsx
"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useState, type ReactNode } from "react";

export function Providers({ children }: { children: ReactNode }) {
  const [queryClient] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: {
            staleTime: 60 * 1000,
            retry: (failureCount, error) => {
              // Don't retry on auth errors
              if (error instanceof Error && error.message === "Unauthorized") {
                return false;
              }
              return failureCount < 3;
            },
          },
        },
      })
  );

  return (
    <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
  );
}
```

#### 2.4 Create Login Page

**File:** `frontend/src/app/login/page.tsx` (create)

> **Review note:** Added Suspense boundary (required for `useSearchParams` in Next.js 14+). Uses new `useAuth` hook from `@/hooks/useAuth`.

```tsx
"use client";

import { Suspense, useEffect } from "react";
import { useSearchParams } from "next/navigation";
import { useAuth } from "@/hooks/useAuth";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Github, AlertCircle } from "lucide-react";

const API_URL = process.env.NEXT_PUBLIC_API_URL || "http://localhost:3000";

function LoginContent() {
  const { isAuthenticated, isLoading } = useAuth();
  const searchParams = useSearchParams();
  const error = searchParams.get("error");

  useEffect(() => {
    if (!isLoading && isAuthenticated) {
      window.location.href = "/";
    }
  }, [isAuthenticated, isLoading]);

  const handleLogin = () => {
    // OmniAuth 2.0 requires POST - create and submit form
    const form = document.createElement("form");
    form.method = "POST";
    form.action = `${API_URL}/auth/github`;
    document.body.appendChild(form);
    form.submit();
  };

  const errorMessage = error
    ? error === "not_in_team"
      ? "Access denied. You must be a member of an authorized team."
      : error === "access_denied"
        ? "You denied access to the application."
        : "An error occurred during authentication. Please try again."
    : null;

  if (isLoading) {
    return <LoginSkeleton />;
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-background p-4">
      <Card className="w-full max-w-md">
        <CardHeader className="text-center">
          <CardTitle className="text-2xl">OpenDXI Dashboard</CardTitle>
          <CardDescription>
            Sign in with GitHub to access developer experience metrics
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {errorMessage && (
            <Alert variant="destructive">
              <AlertCircle className="h-4 w-4" />
              <AlertDescription>{errorMessage}</AlertDescription>
            </Alert>
          )}

          <Button onClick={handleLogin} className="w-full" size="lg">
            <Github className="mr-2 h-5 w-5" />
            Sign in with GitHub
          </Button>

          <p className="text-xs text-muted-foreground text-center">
            Only members of authorized GitHub teams can access this application.
          </p>
        </CardContent>
      </Card>
    </div>
  );
}

function LoginSkeleton() {
  return (
    <div className="min-h-screen flex items-center justify-center">
      <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary" />
    </div>
  );
}

export default function LoginPage() {
  return (
    <Suspense fallback={<LoginSkeleton />}>
      <LoginContent />
    </Suspense>
  );
}
```

#### 2.5 ~~Route Protection Middleware~~ (REMOVED)

> **Review note:** Next.js middleware was removed from this plan. It cannot validate sessions (only check if cookie exists), making it "security theater." The API returns 401 for unauthenticated requests, and `api.ts` already handles redirects to `/login` on 401 responses (see section 2.1, lines 409-415). Single source of truth is better.

#### 2.6 Create User Menu Component

**File:** `frontend/src/components/layout/UserMenu.tsx` (create)

> **Review note:** Moved from `ui/` to `layout/` directory. The `ui/` directory is for shadcn primitives; this is a domain-specific component. Uses new `useAuth` hook.

```tsx
"use client";

import { useAuth } from "@/hooks/useAuth";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { LogOut } from "lucide-react";

export function UserMenu() {
  const { user, logout, isLoading } = useAuth();

  if (isLoading || !user) return null;

  const initials =
    user.name
      ?.split(" ")
      .map((n) => n[0])
      .join("")
      .toUpperCase() || user.login[0].toUpperCase();

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <button className="rounded-full focus:outline-none focus:ring-2 focus:ring-ring">
          <Avatar className="h-8 w-8">
            <AvatarImage src={user.avatar_url} alt={user.name || user.login} />
            <AvatarFallback>{initials}</AvatarFallback>
          </Avatar>
        </button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-56">
        <DropdownMenuLabel>
          <span className="font-medium">{user.name || user.login}</span>
          <span className="block text-xs text-muted-foreground">@{user.login}</span>
        </DropdownMenuLabel>
        <DropdownMenuSeparator />
        <DropdownMenuItem onClick={logout} className="text-destructive cursor-pointer">
          <LogOut className="mr-2 h-4 w-4" />
          Sign out
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
```

#### 2.7 Update Dashboard Header

The existing dashboard header should include the `UserMenu` component:

```tsx
import { UserMenu } from "@/components/layout/UserMenu";

// In the header JSX:
<header className="...">
  {/* ... existing header content ... */}
  <UserMenu />
</header>
```

### Phase 3: Deployment Configuration

#### 3.1 Create GitHub OAuth App

1. Go to https://github.com/organizations/[your-org]/settings/applications
2. Click "New OAuth App"
3. Configure:
   - **Application name:** OpenDXI Dashboard
   - **Homepage URL:** `https://dxi.esoxjem.com`
   - **Authorization callback URL:** `https://dxi-api.esoxjem.com/auth/github/callback`
4. Note the Client ID and generate a Client Secret

#### 3.2 Coolify Environment Variables

Set these in Coolify for the Rails API service:

```bash
# OAuth credentials
GITHUB_OAUTH_CLIENT_ID=Ov23li...
GITHUB_OAUTH_CLIENT_SECRET=your_secret
GITHUB_OAUTH_CALLBACK_URL=https://dxi-api.esoxjem.com/auth/github/callback

# Authorization
GITHUB_ALLOWED_TEAMS=engineering

# Cross-origin
CORS_ORIGINS=https://dxi.esoxjem.com
FRONTEND_URL=https://dxi.esoxjem.com

# Session secret (generate with: rails secret)
SECRET_KEY_BASE=your_secret_key_base
```

#### 3.3 Update Production CORS

Ensure production environment allows the correct origins with credentials.

## Acceptance Criteria

### Functional Requirements

- [ ] Unauthenticated users are redirected to login page
- [ ] Login page shows "Sign in with GitHub" button
- [ ] Clicking login redirects to GitHub OAuth consent page
- [ ] After GitHub authorization, user is redirected back to app
- [ ] Users NOT in allowed teams see "Access Denied" error
- [ ] Users IN allowed teams can access the dashboard
- [ ] User avatar and name shown in header
- [ ] Logout button clears session and redirects to login
- [ ] Session persists across page refreshes
- [ ] Session works correctly across browser tabs

### Non-Functional Requirements

- [ ] OAuth flow completes in under 3 seconds
- [ ] Session cookies use `HttpOnly`, `Secure`, `SameSite=None`
- [ ] No sensitive tokens exposed to frontend JavaScript
- [ ] Health check endpoint (`/up`) remains public for Coolify

### Quality Gates

- [ ] All existing tests pass
- [ ] New auth endpoints have test coverage
- [ ] Manual testing on staging before production deploy
- [ ] OAuth works in both development and production environments

## Dependencies & Prerequisites

### External Dependencies

| Dependency | Purpose | Version |
|------------|---------|---------|
| omniauth | OAuth framework | ~> 2.1 |
| omniauth-github | GitHub OAuth strategy | ~> 2.0 |
| omniauth-rails_csrf_protection | CSRF security | latest |

### Prerequisites

1. GitHub OAuth App created with correct callback URL
2. Knowledge of which GitHub teams should have access
3. HTTPS enabled on both frontend and API domains (required for secure cookies)

## Risk Analysis & Mitigation

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Cookie not sent cross-origin | Auth broken | Medium | Test thoroughly with `credentials: include` |
| Safari ITP blocks cookies | Safari users locked out | Low | Monitor, consider same-domain architecture |
| GitHub API down during auth | Users can't login | Low | Show friendly error, suggest retry |
| Team membership stale | Revoked user keeps access | Low | MVP accepts this; add periodic re-check in v2 |

## Alternative Architecture (If Cookie Issues Arise)

> **Review note:** If cross-origin cookies prove problematic (Safari ITP), this is the recommended fallback.

**Same-domain with reverse proxy** (preferred):
```
dxi.esoxjem.com/* → Next.js frontend
dxi.esoxjem.com/api/* → Rails API (via Coolify reverse proxy)
```

Benefits:
- No cross-origin cookies = no `SameSite=None`, no Safari ITP issues
- No CORS configuration needed
- Simpler cookie setup (standard `SameSite=Lax`)

## References & Research

### Internal References

- Current CORS config: `api/config/initializers/cors.rb`
- GitHub service (existing): `api/app/services/github_service.rb:1`
- API base controller: `api/app/controllers/api/base_controller.rb:1`
- Coolify deployment plan: `plans/feat-deploy-to-coolify.md`

### External References

- [OmniAuth GitHub Strategy](https://github.com/omniauth/omniauth-github)
- [OmniAuth 2.0 Breaking Changes](https://github.com/omniauth/omniauth/wiki/Upgrading-to-2.0)
- [GitHub Teams API](https://docs.github.com/en/rest/teams/members)
- [Rails 8 API-only Sessions](https://guides.rubyonrails.org/api_app.html)
- [rack-cors Credentials](https://github.com/cyu/rack-cors#credentials)
- [Coolify OAuth Variables](https://coolify.io/docs/knowledge-base/environment-variables)

## Files to Create/Modify Summary

### New Files

| File | Purpose |
|------|---------|
| `api/config/initializers/omniauth.rb` | OmniAuth GitHub configuration |
| `api/app/controllers/sessions_controller.rb` | OAuth callback handler + logout |
| `api/app/controllers/api/auth_controller.rb` | Auth status endpoint only |
| `frontend/src/hooks/useAuth.ts` | TanStack Query auth hook |
| `frontend/src/app/login/page.tsx` | Login page UI |
| `frontend/src/components/layout/UserMenu.tsx` | User dropdown menu |

### Modified Files

| File | Changes |
|------|---------|
| `api/Gemfile` | Add omniauth gems |
| `api/config/application.rb` | Re-enable session middleware |
| `api/config/routes.rb` | Add OAuth routes |
| `api/config/initializers/cors.rb` | Add `/auth/*` and `credentials: true` |
| `api/config/initializers/opendxi.rb` | Add allowed_teams config |
| `api/app/controllers/api/base_controller.rb` | Add authentication |
| `api/app/services/github_service.rb` | Add team verification class methods |
| `api/.env.example` | Add OAuth env vars |
| `frontend/src/lib/api.ts` | Add `credentials: include` + auth functions |
| `frontend/src/app/providers.tsx` | Add retry logic for auth errors |

### Files NOT Created (Removed After Review)

| File | Reason |
|------|--------|
| ~~`api/app/services/github_team_verifier.rb`~~ | Methods added to existing `GithubService` instead |
| ~~`frontend/src/contexts/AuthContext.tsx`~~ | Replaced with TanStack Query `useAuth` hook |
| ~~`frontend/src/middleware.ts`~~ | Cannot validate sessions client-side; API handles auth |

## Database Changes

**None required.** This implementation uses encrypted cookie sessions.
