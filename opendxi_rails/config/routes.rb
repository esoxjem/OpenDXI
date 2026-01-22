Rails.application.routes.draw do
  # ═══════════════════════════════════════════════════════════════════════════
  # API Routes (for Next.js frontend)
  # ═══════════════════════════════════════════════════════════════════════════
  namespace :api do
    get "health", to: "health#show"
    get "config", to: "config#show"

    # Sprint endpoints
    get "sprints", to: "sprints#index"
    get "sprints/history", to: "sprints#history"
    get "sprints/:start_date/:end_date/metrics", to: "sprints#metrics", as: :sprint_metrics

    # Developer endpoints
    get "developers/:name/history", to: "developers#history", as: :developer_history
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # HTML Routes (Hotwire dashboard - kept for reference/admin)
  # ═══════════════════════════════════════════════════════════════════════════
  root "dashboard#show"
  get "dashboard", to: "dashboard#show"
  post "dashboard/refresh", to: "dashboard#refresh"

  # Developer detail (Turbo Frame target)
  get "developers/:login", to: "developers#show", as: :developer
  get "developers/:login/history", to: "developers#history", as: :html_developer_history

  # Sprint history for trend charts
  get "sprints/history", to: "sprints#history"

  # Health check (built-in Rails health check)
  get "up" => "rails/health#show", as: :rails_health_check
end
