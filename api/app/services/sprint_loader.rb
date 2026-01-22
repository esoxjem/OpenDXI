# frozen_string_literal: true

# Orchestrates Sprint data loading with dependency injection for testability.
#
# Separates the data fetching concern from the Sprint model, following the
# Dependency Inversion Principle. The fetcher can be injected for testing
# or swapped for alternative data sources.
#
# Usage:
#   SprintLoader.new.load(start_date, end_date)
#   SprintLoader.new.load(start_date, end_date, force: true)
#   SprintLoader.new(fetcher: MockFetcher).load(...)  # for testing
class SprintLoader
  # @param fetcher [#fetch_sprint_data] Any object that responds to fetch_sprint_data(start_date, end_date)
  def initialize(fetcher: GithubService)
    @fetcher = fetcher
  end

  # Load sprint data, optionally forcing a refresh from the data source.
  #
  # Uses transaction with retry on RecordNotUnique to handle race conditions
  # when multiple concurrent requests try to create the same sprint.
  #
  # @param start_date [Date, String] Sprint start date
  # @param end_date [Date, String] Sprint end date
  # @param force [Boolean] When true, refetch data even if cached
  # @return [Sprint] The loaded or created Sprint record
  def load(start_date, end_date, force: false)
    start_date = Date.parse(start_date.to_s)
    end_date = Date.parse(end_date.to_s)

    Sprint.transaction do
      sprint = Sprint.find_by_dates(start_date, end_date)
      return sprint if sprint && !force

      data = @fetcher.fetch_sprint_data(start_date, end_date)

      if sprint
        sprint.update!(data: data)
        sprint
      else
        Sprint.create!(start_date: start_date, end_date: end_date, data: data)
      end
    end
  rescue ActiveRecord::RecordNotUnique
    # Another request created the sprint while we were fetching data
    Sprint.find_by_dates(start_date, end_date)
  end
end
