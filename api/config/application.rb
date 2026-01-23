require_relative "boot"

require "rails"
# Pick the frameworks you want (API-only mode):
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
# require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
# require "action_view/railtie"  # Not needed for API-only
# require "action_cable/engine"  # Not needed for API-only
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module OpendxiRails
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # API-only mode - but with sessions for OAuth
    config.api_only = true

    # Re-add session middleware for OAuth (required for API-only mode)
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore,
      key: "_opendxi_session",
      # SameSite=None requires Secure=true, which doesn't work in dev (http)
      # Use Lax in development (works for same-site navigation from different ports)
      # Use None+Secure in production (works for true cross-origin with HTTPS)
      same_site: Rails.env.production? ? :none : :lax,
      secure: Rails.env.production?,
      httponly: true  # Explicit is better than implicit for security

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Add serializer concerns to autoload paths (not included by default like model/controller concerns)
    config.autoload_paths << Rails.root.join("app/serializers/concerns")

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
