# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# Configure OmniAuth for testing
OmniAuth.config.test_mode = true

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

# Authentication helpers for integration tests
module AuthenticationTestHelper
  # Sign in a user via the test-only auth endpoint
  #
  # @param user_or_attrs [User, Hash] User instance or attributes hash
  # @return [User] The user that was signed in
  def sign_in_as(user_or_attrs = {})
    user_attrs = if user_or_attrs.is_a?(User)
                   {
                     github_id: user_or_attrs.github_id,
                     login: user_or_attrs.login,
                     name: user_or_attrs.name,
                     avatar_url: user_or_attrs.avatar_url,
                     role: user_or_attrs.role
                   }
                 else
                   default_user.merge(user_or_attrs)
                 end

    # Ensure unique github_id and login for each test
    user_attrs[:github_id] ||= SecureRandom.random_number(1_000_000)
    user_attrs[:login] ||= "test-user-#{SecureRandom.hex(4)}"

    post "/test/auth", params: { user: user_attrs }

    # Return the user that was created
    User.find_by!(github_id: user_attrs[:github_id])
  end

  # Set up OmniAuth mock for testing OAuth flow (use for SessionsController tests)
  def mock_github_auth(user_info = default_user)
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new({
      provider: "github",
      uid: user_info[:github_id].to_s,
      info: {
        nickname: user_info[:login],
        name: user_info[:name],
        image: user_info[:avatar_url]
      },
      credentials: {
        token: "mock_token"
      }
    })
  end

  def default_user
    {
      github_id: 12345,
      login: "testuser",
      name: "Test User",
      avatar_url: "https://github.com/images/testuser.png",
      role: :developer
    }
  end
end

class ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
end
