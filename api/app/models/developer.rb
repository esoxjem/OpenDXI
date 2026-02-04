# frozen_string_literal: true

# Developer model - tracks GitHub org members and external contributors for metrics display
#
# Separate from User (access control). Developers represent people whose metrics
# appear on the dashboard, regardless of whether they can log in.
#
# Sources:
#   - org_member: Synced from GitHub org members API
#   - external: Auto-created from sprint data (contributors not in the org)
class Developer < ApplicationRecord
  has_many :team_memberships, dependent: :destroy
  has_many :teams, through: :team_memberships

  validates :github_id, presence: true, uniqueness: true
  validates :github_login, presence: true, uniqueness: true
  validates :source, inclusion: { in: %w[org_member external] }

  scope :visible, -> { where(visible: true) }
  scope :org_members, -> { where(source: "org_member") }

  def self.visible_logins
    visible.pluck(:github_login)
  end
end
