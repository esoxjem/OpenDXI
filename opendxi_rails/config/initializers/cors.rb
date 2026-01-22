# frozen_string_literal: true

# CORS configuration for API endpoints
#
# Allows the Next.js frontend to make cross-origin requests to the Rails API.
# In development, allows localhost:3000. In production, configure via CORS_ORIGINS env var.

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*ENV.fetch("CORS_ORIGINS", "http://localhost:3000").split(",").map(&:strip))

    resource "/api/*",
      headers: :any,
      methods: %i[get post put patch delete options head],
      max_age: 86400
  end
end
