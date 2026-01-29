# frozen_string_literal: true

# Test-only controller for setting up authenticated sessions
# This controller is only available in the test environment
class TestAuthController < ActionController::API
  include ActionController::Cookies

  # POST /test/auth - for integration tests
  def create
    return head :not_found unless Rails.env.test?

    set_session
    head :ok
  end

  # GET /test/auth/login - for system tests (Capybara visits this URL)
  def login
    return head :not_found unless Rails.env.test?

    set_session
    redirect_to root_path
  end

  private

  def set_session
    # Convert to hash with symbol keys to match SessionsController behavior
    user_params = params.require(:user).permit(:github_id, :login, :name, :avatar_url)
    session[:user] = {
      github_id: user_params[:github_id],
      login: user_params[:login],
      name: user_params[:name],
      avatar_url: user_params[:avatar_url]
    }
    session[:authenticated_at] = Time.current.iso8601
  end
end
