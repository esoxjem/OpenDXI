# frozen_string_literal: true

class JobStatus < ApplicationRecord
  VALID_STATUSES = %w[ok partial failed].freeze

  validates :name, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: VALID_STATUSES }

  VALID_STATUSES.each do |s|
    define_method("#{s}?") { status == s }
  end

  def self.github_refresh
    find_by(name: "github_refresh")
  end
end
