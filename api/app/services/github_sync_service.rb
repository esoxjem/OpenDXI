# frozen_string_literal: true

# Syncs GitHub org members and teams into the local database.
#
# Responsibilities:
#   1. Fetch org members → create/update Developer records (source: "org_member")
#   2. Fetch GitHub teams → create/update Team records (source: "github")
#   3. Sync team memberships (skip diverged teams)
#   4. Detect external contributors in sprint data → create Developer records (source: "external")
#
# Usage:
#   GithubSyncService.new.sync_all
#   GithubSyncService.new(github: MockService).sync_all  # for testing
class GithubSyncService
  # @param github [#fetch_org_members, #fetch_org_teams, #fetch_team_members]
  def initialize(github: GithubService)
    @github = github
  end

  # Runs the full sync: org members, teams, and external contributors.
  #
  # @return [Hash] Summary of synced counts
  def sync_all
    members_count = sync_org_members
    teams_count = sync_teams
    external_count = sync_external_contributors

    {
      members_synced: members_count,
      teams_synced: teams_count,
      external_detected: external_count
    }
  end

  # Syncs org members from GitHub into the developers table.
  # Additive: new members are added, existing ones updated, none deleted.
  #
  # @return [Integer] Number of developers synced
  def sync_org_members
    members = @github.fetch_org_members
    count = 0

    members.each do |member|
      dev = Developer.find_or_initialize_by(github_id: member["id"])
      dev.assign_attributes(
        github_login: member["login"],
        avatar_url: member["avatar_url"],
        source: "org_member"
      )
      dev.save!
      count += 1
    rescue ActiveRecord::RecordNotUnique
      # Handle race condition: another process created this developer
      count += 1
    end

    count
  end

  # Syncs GitHub teams into the teams table and their memberships.
  # Skips membership updates for locally diverged teams (synced: false).
  #
  # @return [Integer] Number of teams synced
  def sync_teams
    github_teams = @github.fetch_org_teams
    count = 0

    github_teams.each do |gh_team|
      team = Team.find_or_initialize_by(github_team_id: gh_team["id"])
      team.assign_attributes(
        name: gh_team["name"],
        slug: gh_team["slug"],
        source: "github"
      )

      # Only mark as synced if it's a new record or was already synced
      team.synced = true if team.new_record? || team.synced?
      team.save!

      # Only update memberships for synced teams (not locally diverged)
      sync_team_members(team, gh_team["slug"]) if team.synced?

      count += 1
    rescue ActiveRecord::RecordNotUnique
      count += 1
    end

    count
  end

  # Scans recent sprint data for developers not in the developers table.
  # Creates Developer records with source: "external" for those found.
  #
  # @return [Integer] Number of external contributors detected
  def sync_external_contributors
    known_logins = Developer.pluck(:github_login)
    sprint_logins = recent_sprint_logins

    new_logins = sprint_logins - known_logins
    count = 0

    new_logins.each do |login|
      Developer.create!(
        github_id: generate_external_id(login),
        github_login: login,
        source: "external",
        visible: true
      )
      count += 1
    rescue ActiveRecord::RecordNotUnique
      # Already created by another process
      count += 1
    end

    count
  end

  private

  def sync_team_members(team, team_slug)
    members = @github.fetch_team_members(team_slug)
    member_github_ids = members.map { |m| m["id"] }

    # Find matching developers in our DB
    developers = Developer.where(github_id: member_github_ids)
    developer_ids = developers.pluck(:id)

    # Replace all memberships for this team
    TeamMembership.where(team: team).where.not(developer_id: developer_ids).delete_all
    developer_ids.each do |dev_id|
      TeamMembership.find_or_create_by!(team: team, developer_id: dev_id)
    rescue ActiveRecord::RecordNotUnique
      # Already exists
    end
  end

  def recent_sprint_logins
    Sprint.order(start_date: :desc).limit(6)
      .flat_map(&:developers)
      .filter_map { |d| d["developer"] || d["github_login"] }
      .uniq
  end

  # Generate a deterministic pseudo-ID for external contributors.
  # Uses a negative hash to avoid conflicts with real GitHub IDs.
  def generate_external_id(login)
    # Use a large offset + hash to create a unique ID that won't collide with real GitHub IDs
    (login.hash.abs % 1_000_000_000) + 9_000_000_000
  end
end
