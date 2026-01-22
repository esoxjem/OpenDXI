Rails.application.routes.draw do
  # Dashboard
  root "dashboard#show"
  get "dashboard", to: "dashboard#show"
  post "dashboard/refresh", to: "dashboard#refresh"

  # Developer detail (Turbo Frame target)
  get "developers/:login", to: "developers#show", as: :developer
  get "developers/:login/history", to: "developers#history", as: :developer_history

  # Sprint history for trend charts
  get "sprints/history", to: "sprints#history"

  # Health check (built-in Rails health check)
  get "up" => "rails/health#show", as: :rails_health_check
end
