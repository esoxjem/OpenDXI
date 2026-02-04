# frozen_string_literal: true

# Shared filtering logic for serializers that support developer visibility
# and team membership filters.
#
# Expects the including class to set:
#   @sprint          [Sprint]              the sprint whose developers to filter
#   @visible_logins  [Set<String>, nil]  restrict to these logins (visibility)
#   @team_logins     [Set<String>, nil]  restrict to these logins (team)
#
# Provides:
#   - filtering?           whether any filter is active
#   - filtered_developers  the developer list after applying active filters
#   - developer_login(dev) canonical login extraction from a developer hash
module DeveloperFilterable
  def filtering?
    @visible_logins.present? || @team_logins.present?
  end

  def filtered_developers
    devs = @sprint.developers
    devs = devs.select { |d| developer_login(d).in?(@visible_logins) } if @visible_logins.present?
    devs = devs.select { |d| developer_login(d).in?(@team_logins) } if @team_logins.present?
    devs
  end

  def developer_login(dev)
    dev["github_login"] || dev["developer"]
  end
end
