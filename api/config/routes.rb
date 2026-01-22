Rails.application.routes.draw do
  # ═══════════════════════════════════════════════════════════════════════════
  # API Routes (JSON API for Next.js frontend)
  # ═══════════════════════════════════════════════════════════════════════════
  namespace :api do
    get "health", to: "health#show"
    get "config", to: "config#show"

    # Sprint endpoints
    get "sprints", to: "sprints#index"
    get "sprints/history", to: "sprints#history"
    get "sprints/:start_date/:end_date/metrics", to: "sprints#metrics", as: :sprint_metrics

    # Developer endpoints
    get "developers", to: "developers#index"
    get "developers/:name/history", to: "developers#history", as: :developer_history
  end

  # Health check (built-in Rails health check)
  get "up" => "rails/health#show", as: :rails_health_check
end
