# frozen_string_literal: true

# Base application controller.
# Note: All API controllers inherit from Api::BaseController (ActionController::API),
# not this controller. This class exists for Rails conventions but is not actively used.
class ApplicationController < ActionController::Base
  # Allow all browsers for health check endpoint
  allow_browser versions: :modern, only: :health_check
end
