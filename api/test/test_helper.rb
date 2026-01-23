ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# Configure OmniAuth for testing
OmniAuth.config.test_mode = true

# Clear allowed_users for tests (the .env file may have real users configured)
# Tests that need to verify authorization behavior will set this explicitly
Rails.application.config.opendxi.allowed_users = []

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
  def sign_in_as(user_info = default_user)
    post "/test/auth", params: { user: user_info }
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
      avatar_url: "https://github.com/images/testuser.png"
    }
  end
end

class ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
end
