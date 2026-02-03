# frozen_string_literal: true

# User model - persists authorized users with role-based access control
#
# Roles:
#   - developer (default): Can view dashboard metrics
#   - owner: Can manage users and access settings
#
# Users are created by owners via the Settings UI (POST /api/users).
# The first owner can be bootstrapped via OWNER_GITHUB_USERNAME env var on first login.
# Users not in the database cannot log in via OAuth.
class User < ApplicationRecord
  enum :role, { developer: 0, owner: 1 }, default: :developer

  validates :github_id, presence: true, uniqueness: true
  validates :login, presence: true, uniqueness: true

  # Generate a default avatar URL for users without one
  #
  # @param login [String] GitHub username
  # @return [String] URL to GitHub's identicon for the user
  def self.default_avatar_url(login)
    "https://github.com/identicons/#{login}.png"
  end
end
