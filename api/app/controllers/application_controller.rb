# frozen_string_literal: true

# Base application controller.
# Note: All API controllers inherit from Api::BaseController (ActionController::API),
# not this controller. This class is only used by SessionsController for OAuth handling.
class ApplicationController < ActionController::Base
  # No browser restrictions for OAuth flow - users may use various browsers
end
