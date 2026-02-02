# frozen_string_literal: true

# User model - persists GitHub OAuth users with role-based access control
#
# Roles:
#   - developer (default): Can view dashboard metrics
#   - owner: Can manage users and access settings
#
# Users are created/updated on OAuth login via #find_or_create_from_github.
# The first owner can be bootstrapped via OWNER_GITHUB_USERNAME env var.
class User < ApplicationRecord
  enum :role, { developer: 0, owner: 1 }, default: :developer

  validates :github_id, presence: true, uniqueness: true
  validates :login, presence: true, uniqueness: true

  # Find or create user from GitHub OAuth hash, with race condition handling
  #
  # @param auth_hash [OmniAuth::AuthHash] The OAuth response from GitHub
  # @return [User] The created or updated user record
  def self.find_or_create_from_github(auth_hash)
    transaction do
      user = find_or_initialize_by(github_id: auth_hash["uid"])

      user.assign_attributes(
        login: auth_hash["info"]["nickname"],
        name: auth_hash["info"]["name"],
        avatar_url: auth_hash["info"]["image"] || default_avatar_url(auth_hash["info"]["nickname"])
      )

      # Bootstrap first owner from env var (first login only)
      if user.new_record? && owner_bootstrap_login?(user.login)
        user.role = :owner
      end

      user.save!
      user
    end
  rescue ActiveRecord::RecordNotUnique
    # Concurrent OAuth callback - retry to find existing record
    retry
  end

  # Check if login matches the owner bootstrap environment variable
  #
  # @param login [String] GitHub username to check
  # @return [Boolean] true if login matches OWNER_GITHUB_USERNAME (case-insensitive)
  def self.owner_bootstrap_login?(login)
    ENV["OWNER_GITHUB_USERNAME"]&.downcase == login&.downcase
  end

  # Generate a default avatar URL for users without one
  #
  # @param login [String] GitHub username
  # @return [String] URL to GitHub's identicon for the user
  def self.default_avatar_url(login)
    "https://github.com/identicons/#{login}.png"
  end
end
