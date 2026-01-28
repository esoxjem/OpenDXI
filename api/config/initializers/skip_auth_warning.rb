# frozen_string_literal: true

# Security check and logging for authentication bypass in development
#
# Auth bypass scenarios (development mode only):
# 1. SKIP_AUTH=true - Explicit bypass via environment variable
# 2. No GitHub OAuth credentials - Auto-bypass for development convenience
#
# In non-development environments, authentication is always required.

if Rails.env.development?
  oauth_configured = ENV["GITHUB_OAUTH_CLIENT_ID"].to_s.strip.present? &&
                     ENV["GITHUB_OAUTH_CLIENT_SECRET"].to_s.strip.present?

  if ENV["SKIP_AUTH"] == "true"
    Rails.logger.info "[Auth] SKIP_AUTH=true - authentication bypassed for local development"
  elsif !oauth_configured
    Rails.logger.info "[Auth] GitHub OAuth not configured - authentication auto-bypassed for local development"
    Rails.logger.info "[Auth] To enable OAuth, set GITHUB_OAUTH_CLIENT_ID and GITHUB_OAUTH_CLIENT_SECRET"
  end
elsif ENV["SKIP_AUTH"] == "true"
  Rails.logger.warn "[Security] SKIP_AUTH=true is set but IGNORED in #{Rails.env} environment"
end
