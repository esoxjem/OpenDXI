Rails.application.routes.draw do
  # ═══════════════════════════════════════════════════════════════════════════
  # Health Check (PUBLIC - no auth required)
  # ═══════════════════════════════════════════════════════════════════════════
  get "up" => "rails/health#show", as: :rails_health_check

  # Test-only route for setting up authenticated sessions in tests
  if Rails.env.test?
    post "test/auth", to: "test_auth#create"
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # OAuth Routes (PUBLIC - handles auth flow)
  # Note: GET /auth/github is handled by OmniAuth middleware automatically
  # ═══════════════════════════════════════════════════════════════════════════
  get "/auth/github/callback", to: "sessions#create"
  get "/auth/failure", to: "sessions#failure"
  delete "/auth/logout", to: "sessions#destroy"

  # ═══════════════════════════════════════════════════════════════════════════
  # API Routes (JSON API for Next.js frontend)
  # ═══════════════════════════════════════════════════════════════════════════
  namespace :api do
    # Auth status endpoint
    get "auth/me", to: "auth#me"

    # Existing endpoints (protected by authentication)
    get "health", to: "health#show"
    get "config", to: "config#show"

    # Sprint endpoints
    get "sprints", to: "sprints#index"
    get "sprints/history", to: "sprints#history"
    get "sprints/:start_date/:end_date/metrics", to: "sprints#metrics", as: :sprint_metrics

    # Developer endpoints
    get "developers", to: "developers#index"
    get "developers/managed", to: "developers#managed"
    patch "developers/:id", to: "developers#update", as: :developer
    post "developers/sync", to: "developers#sync"
    get "developers/:name/history", to: "developers#history", as: :developer_history

    # Team management
    resources :teams, only: [:index, :show, :create, :update, :destroy]

    # User management (owner-only)
    resources :users, only: [:index, :create, :update, :destroy]
  end
end
