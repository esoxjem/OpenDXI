Rails.application.routes.draw do
  # ═══════════════════════════════════════════════════════════════════════════
  # Health Check (PUBLIC - for Docker/Coolify monitoring)
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
  # Dashboard Routes (Full-stack Rails views)
  # ═══════════════════════════════════════════════════════════════════════════
  root "dashboard#index"

  get "login", to: "sessions#new", as: :login

  # Dashboard with view param for tab content
  # GET /?view=team (default)
  # GET /?view=developers&developer=alice
  # GET /?view=history
  get "dashboard", to: "dashboard#index"

  # Refresh action - fetches fresh data from GitHub
  post "dashboard/refresh", to: "dashboard#refresh"

  # ═══════════════════════════════════════════════════════════════════════════
  # API Routes (Minimal - health check only for external monitoring)
  # ═══════════════════════════════════════════════════════════════════════════
  namespace :api do
    get "health", to: "health#show"
  end
end
