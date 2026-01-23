# frozen_string_literal: true

# CORS configuration for API and OAuth endpoints
#
# Allows the Next.js frontend to make cross-origin requests to the Rails API.
# In development, allows localhost:3001. In production, configure via CORS_ORIGINS env var.
#
# IMPORTANT: credentials: true is required for session cookies to work cross-origin

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*ENV.fetch("CORS_ORIGINS", "http://localhost:3001").split(",").map(&:strip))

    # OAuth routes
    resource "/auth/*",
      headers: :any,
      methods: %i[get delete options],
      credentials: true

    # API routes
    resource "/api/*",
      headers: :any,
      methods: %i[get post put patch delete options head],
      credentials: true,
      max_age: 86400
  end
end
