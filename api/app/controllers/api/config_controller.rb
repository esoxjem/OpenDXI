# frozen_string_literal: true

module Api
  class ConfigController < BaseController
    # GET /api/config
    def show
      render json: {
        github_org: Rails.application.config.opendxi.github_org
      }
    end
  end
end
