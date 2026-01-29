# frozen_string_literal: true

# Content Security Policy configuration for full-stack Rails with Hotwire
#
# See: https://guides.rubyonrails.org/security.html#content-security-policy-header
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :data
    policy.img_src     :self, :data, "https:"
    policy.object_src  :none
    # Allow 'unsafe-inline' for Chartkick's inline chart initialization scripts
    # and 'unsafe-eval' for Chart.js internals
    policy.script_src  :self, :unsafe_inline, :unsafe_eval
    policy.style_src   :self, :unsafe_inline
    policy.frame_ancestors :none

    # Allow WebSocket connections for Turbo in development
    if Rails.env.development?
      policy.connect_src :self, "ws://localhost:*"
    else
      policy.connect_src :self
    end
  end
end
