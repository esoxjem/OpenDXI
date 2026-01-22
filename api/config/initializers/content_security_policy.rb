# frozen_string_literal: true

# Content Security Policy configuration for API-only mode
#
# Since this is a JSON API with no HTML responses, CSP is minimal.
# The frontend (Next.js) handles its own CSP.
#
# See: https://guides.rubyonrails.org/security.html#content-security-policy-header
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :none
    policy.frame_ancestors :none
  end
end
