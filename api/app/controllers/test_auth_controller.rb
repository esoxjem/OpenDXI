# frozen_string_literal: true

# Test-only controller for setting up authenticated sessions
# This controller is only available in the test environment
class TestAuthController < ActionController::API
  include ActionController::Cookies

  def create
    return head :not_found unless Rails.env.test?

    session[:user] = params.require(:user).permit(:github_id, :login, :name, :avatar_url).to_h
    session[:authenticated_at] = Time.current.iso8601

    head :ok
  end
end
