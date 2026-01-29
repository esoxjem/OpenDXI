# frozen_string_literal: true

# CORS configuration for API endpoints
#
# Since the frontend is now server-rendered by Rails, CORS is only needed for:
# - External API consumers (if any)
# - Local development with external tools
#
# Configure origins via CORS_ORIGINS env var if needed.

if ENV["CORS_ORIGINS"].present?
  Rails.application.config.middleware.insert_before 0, Rack::Cors do
    allow do
      origins(*ENV["CORS_ORIGINS"].split(",").map(&:strip))

      resource "/api/*",
        headers: :any,
        methods: %i[get post put patch delete options head],
        credentials: true,
        max_age: 86400
    end
  end
end
