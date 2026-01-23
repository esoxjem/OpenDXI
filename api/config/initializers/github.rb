Rails.application.config.after_initialize do
  if Rails.env.production? && ENV["GH_TOKEN"].blank?
    Rails.logger.error("FATAL: GH_TOKEN environment variable must be set in production")
    # Note: App boots, health check works, but API calls will fail gracefully
  end
end
