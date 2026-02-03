# frozen_string_literal: true

# OpenDXI Configuration
# Configure settings for DXI dashboard from environment variables
Rails.application.configure do
  config.opendxi = ActiveSupport::OrderedOptions.new
  config.opendxi.github_org = ENV.fetch("GITHUB_ORG", nil)
  config.opendxi.sprint_start_date = Date.parse(ENV.fetch("SPRINT_START_DATE", "2026-01-07"))
  config.opendxi.sprint_duration_days = ENV.fetch("SPRINT_DURATION_DAYS", "14").to_i
  config.opendxi.max_pages_per_query = ENV.fetch("MAX_PAGES_PER_QUERY", "10").to_i
end
