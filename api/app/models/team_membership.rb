# frozen_string_literal: true

# Join model for the many-to-many relationship between developers and teams.
# A developer can belong to multiple teams (e.g., "Backend" and "Platform").
class TeamMembership < ApplicationRecord
  belongs_to :developer
  belongs_to :team

  validates :developer_id, uniqueness: { scope: :team_id }
end
