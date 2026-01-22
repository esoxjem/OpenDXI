# frozen_string_literal: true

namespace :opendxi do
  desc "Migrate data from legacy Python SQLite store to Rails schema"
  task migrate_legacy: :environment do
    require "sqlite3"

    # Legacy database path (relative to project root, not opendxi_rails)
    legacy_db_path = ENV.fetch("LEGACY_DB_PATH", "../.data/opendxi.db")
    legacy_db_path = File.expand_path(legacy_db_path, Rails.root)

    unless File.exist?(legacy_db_path)
      puts "Legacy database not found at #{legacy_db_path}"
      puts "Set LEGACY_DB_PATH environment variable to specify location"
      exit 1
    end

    puts "Opening legacy database: #{legacy_db_path}"

    db = SQLite3::Database.new(legacy_db_path)
    db.results_as_hash = true

    # Check if the table exists (handle both old and new names)
    table_name = nil
    %w[sprints sprint_cache sprint_data].each do |name|
      result = db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='#{name}'")
      if result.any?
        table_name = name
        break
      end
    end

    unless table_name
      puts "No sprint data table found in legacy database"
      exit 1
    end

    puts "Found table: #{table_name}"

    migrated = 0
    errors = []

    db.execute("SELECT * FROM #{table_name}") do |row|
      begin
        # Handle different column naming conventions
        data_json = row["data_json"] || row["data"]
        sprint_start = row["sprint_start"] || row["start_date"]
        sprint_end = row["sprint_end"] || row["end_date"]

        # If dates are in the key, extract them
        if sprint_start.nil? && row["sprint_key"]
          parts = row["sprint_key"].split("_")
          sprint_start = parts[1] if parts.length >= 2
          sprint_end = parts[2] if parts.length >= 3
        end

        next if sprint_start.nil? || sprint_end.nil?

        data = JSON.parse(data_json)

        # Create or update sprint
        Sprint.find_or_create_by!(
          start_date: Date.parse(sprint_start),
          end_date: Date.parse(sprint_end)
        ) do |sprint|
          sprint.data = data
        end

        migrated += 1
        print "."
      rescue StandardError => e
        key = row["sprint_key"] || "#{sprint_start}_#{sprint_end}"
        errors << { key: key, error: e.message }
        print "E"
      end
    end

    puts "\n\nMigration complete: #{migrated} sprints migrated"

    if errors.any?
      puts "\nErrors (#{errors.size}):"
      errors.each { |e| puts "  #{e[:key]}: #{e[:error]}" }
    end

    # Recalculate scores to ensure consistency with Rails DXI algorithm
    puts "\nRecalculating DXI scores..."
    Sprint.find_each do |sprint|
      sprint.recalculate_scores! if sprint.data.present?
      print "."
    end
    puts "\nDone!"
  end

  desc "Verify migration data integrity"
  task verify_migration: :environment do
    puts "Verifying sprint data integrity...\n"

    Sprint.find_each do |sprint|
      errors = []
      errors << "missing data" if sprint.data.blank?
      errors << "missing developers" if sprint.developers.empty? && sprint.data.present?
      errors << "missing summary" if sprint.summary.empty? && sprint.data.present?

      if sprint.developers.any?
        invalid_scores = sprint.developers.count { |d| d["dxi_score"].nil? }
        errors << "#{invalid_scores} developers with invalid scores" if invalid_scores > 0
      end

      if errors.any?
        puts "#{sprint.label}: #{errors.join(', ')}"
      else
        dev_count = sprint.developers.size
        avg_score = sprint.summary["avg_dxi_score"]&.round(1) || "N/A"
        puts "#{sprint.label}: OK (#{dev_count} developers, avg DXI: #{avg_score})"
      end
    end

    total = Sprint.count
    puts "\nTotal sprints: #{total}"
  end

  desc "Clear all sprint data (use with caution!)"
  task clear_data: :environment do
    puts "This will delete ALL sprint data. Are you sure? (yes/no)"
    confirmation = $stdin.gets.chomp.downcase

    if confirmation == "yes"
      count = Sprint.count
      Sprint.delete_all
      puts "Deleted #{count} sprints"
    else
      puts "Aborted"
    end
  end

  desc "Show sprint data statistics"
  task stats: :environment do
    puts "Sprint Data Statistics"
    puts "=" * 40

    total = Sprint.count
    puts "Total sprints: #{total}"

    if total > 0
      oldest = Sprint.order(:start_date).first
      newest = Sprint.order(start_date: :desc).first
      puts "Date range: #{oldest.start_date} to #{newest.end_date}"

      total_devs = Sprint.sum { |s| s.developers.size }
      puts "Total developer entries: #{total_devs}"

      avg_score = Sprint.all.sum { |s| s.summary["avg_dxi_score"] || 0 } / total
      puts "Average team DXI: #{avg_score.round(1)}"
    end
  end
end
