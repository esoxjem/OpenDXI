# frozen_string_literal: true

# Security check for SKIP_AUTH environment variable
#
# SKIP_AUTH=true bypasses authentication but ONLY works in development mode.
# This initializer warns if SKIP_AUTH is set in non-development environments
# and logs when auth bypass is active in development.

if ENV["SKIP_AUTH"] == "true"
  if Rails.env.development?
    Rails.logger.info "[Auth] SKIP_AUTH=true - authentication bypassed for local development"
  else
    Rails.logger.warn "[Security] SKIP_AUTH=true is set but IGNORED in #{Rails.env} environment"
  end
end
