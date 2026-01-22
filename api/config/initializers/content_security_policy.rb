# frozen_string_literal: true

# Content Security Policy configuration
#
# CSP provides defense-in-depth against XSS attacks by restricting
# which sources can load scripts, styles, images, etc.
#
# See: https://guides.rubyonrails.org/security.html#content-security-policy-header
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :data
    policy.img_src     :self, :data, "https://github.com", "https://avatars.githubusercontent.com"
    policy.object_src  :none
    policy.script_src  :self
    policy.style_src   :self, :unsafe_inline  # Required for Tailwind CSS
    policy.connect_src :self
    policy.frame_ancestors :none
    policy.base_uri    :self
    policy.form_action :self
  end

  # Generate session nonces for permitted importmap and inline scripts
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w[script-src]
end
