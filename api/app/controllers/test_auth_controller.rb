# frozen_string_literal: true

# Test-only controller for setting up authenticated sessions
# This controller is only available in the test environment
class TestAuthController < ActionController::API
  include ActionController::Cookies

  def create
    return head :not_found unless Rails.env.test?

    user_params = params.require(:user).permit(:github_id, :login, :name, :avatar_url, :role)

    # Create or find user for testing
    user = User.find_or_initialize_by(github_id: user_params[:github_id])
    user.assign_attributes(
      login: user_params[:login],
      name: user_params[:name],
      avatar_url: user_params[:avatar_url] || "",
      role: user_params[:role] || :developer
    )
    user.save!

    session[:user_id] = user.id
    session[:authenticated_at] = Time.current.iso8601

    head :ok
  end
end
