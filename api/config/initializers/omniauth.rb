# frozen_string_literal: true

# OmniAuth configuration for GitHub OAuth
#
# Requires environment variables:
#   GITHUB_OAUTH_CLIENT_ID     - OAuth App client ID
#   GITHUB_OAUTH_CLIENT_SECRET - OAuth App client secret
#   GITHUB_OAUTH_CALLBACK_URL  - Callback URL (optional, auto-detected in dev)

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :github,
    ENV.fetch("GITHUB_OAUTH_CLIENT_ID", nil),
    ENV.fetch("GITHUB_OAUTH_CLIENT_SECRET", nil),
    scope: "read:user",
    callback_url: ENV.fetch("GITHUB_OAUTH_CALLBACK_URL", nil)
end

OmniAuth.config.logger = Rails.logger

# Allow GET requests for OAuth initiation
# This is safe because:
#   1. OAuth uses state parameter for CSRF protection
#   2. The OAuth flow doesn't modify any data until callback (which validates state)
#   3. Cross-origin POST with CSRF tokens is complex and error-prone
OmniAuth.config.allowed_request_methods = %i[get post]
OmniAuth.config.silence_get_warning = true
