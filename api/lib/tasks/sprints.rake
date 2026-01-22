# frozen_string_literal: true

namespace :sprints do
  desc "Refresh all sprints with empty daily_activity (parallel fetch, serial write)"
  task refresh_empty: :environment do
    sprints_to_fix = Sprint.all.select { |s| (s.data["daily_activity"] || []).empty? }

    if sprints_to_fix.empty?
      puts "✓ All sprints already have daily_activity data"
      exit
    end

    puts "Found #{sprints_to_fix.count} sprints with empty daily_activity:"
    sprints_to_fix.each { |s| puts "  - #{s.start_date} to #{s.end_date}" }
    puts ""

    # Step 1: Fetch all data in parallel (this is the slow GitHub API part)
    puts "Fetching data from GitHub in parallel..."
    results = {}
    threads = []

    sprints_to_fix.each do |sprint|
      threads << Thread.new do
        key = "#{sprint.start_date}/#{sprint.end_date}"
        begin
          data = GithubService.fetch_sprint_data(sprint.start_date.to_s, sprint.end_date.to_s)
          results[key] = { success: true, data: data, sprint: sprint }
          puts "  ✓ Fetched #{key}"
        rescue => e
          results[key] = { success: false, error: e.message, sprint: sprint }
          puts "  ✗ Failed #{key}: #{e.message}"
        end
      end
    end

    threads.each(&:join)
    puts ""

    # Step 2: Write to database serially (avoids SQLite locking)
    puts "Writing to database serially..."
    results.each do |key, result|
      next unless result[:success]

      sprint = result[:sprint]
      begin
        sprint.update!(data: result[:data])
        daily_count = (result[:data]["daily_activity"] || []).length
        puts "  ✓ Saved #{key} (#{daily_count} daily entries)"
      rescue => e
        puts "  ✗ Failed to save #{key}: #{e.message}"
      end
    end

    puts ""
    puts "Done!"
  end

  desc "Refresh all sprints (parallel fetch, serial write)"
  task refresh_all: :environment do
    config = Rails.application.config.opendxi
    duration = config.sprint_duration_days
    current_start, _ = Sprint.current_sprint_dates

    # Generate 6 sprints working backwards
    sprint_dates = 6.times.map do |i|
      start_date = current_start - (i * duration).days
      end_date = start_date + (duration - 1).days
      [start_date, end_date]
    end

    puts "Refreshing #{sprint_dates.count} sprints:"
    sprint_dates.each { |s, e| puts "  - #{s} to #{e}" }
    puts ""

    # Step 1: Fetch all data in parallel
    puts "Fetching data from GitHub in parallel..."
    results = {}
    threads = []

    sprint_dates.each do |start_date, end_date|
      threads << Thread.new do
        key = "#{start_date}/#{end_date}"
        begin
          data = GithubService.fetch_sprint_data(start_date.to_s, end_date.to_s)
          results[key] = { success: true, data: data, start_date: start_date, end_date: end_date }
          puts "  ✓ Fetched #{key}"
        rescue => e
          results[key] = { success: false, error: e.message }
          puts "  ✗ Failed #{key}: #{e.message}"
        end
      end
    end

    threads.each(&:join)
    puts ""

    # Step 2: Write to database serially
    puts "Writing to database serially..."
    results.each do |key, result|
      next unless result[:success]

      begin
        sprint = Sprint.find_or_initialize_by(
          start_date: result[:start_date],
          end_date: result[:end_date]
        )
        sprint.data = result[:data]
        sprint.save!
        daily_count = (result[:data]["daily_activity"] || []).length
        puts "  ✓ Saved #{key} (#{daily_count} daily entries)"
      rescue => e
        puts "  ✗ Failed to save #{key}: #{e.message}"
      end
    end

    puts ""
    puts "Done!"
  end
end
