# frozen_string_literal: true

# Team model - groups developers for dashboard filtering
#
# Sources:
#   - github: Imported from GitHub Teams API
#   - custom: Manually created by owner
#
# The `synced` flag tracks whether a GitHub-imported team's membership
# still matches GitHub. When an owner edits membership locally, `synced`
# is set to false and re-sync won't overwrite the local changes.
class Team < ApplicationRecord
  has_many :team_memberships, dependent: :destroy
  has_many :developers, through: :team_memberships

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :source, inclusion: { in: %w[github custom] }

  before_validation :generate_slug, on: :create

  scope :github_teams, -> { where(source: "github") }
  scope :custom_teams, -> { where(source: "custom") }

  private

  def generate_slug
    self.slug ||= name&.parameterize
  end
end
