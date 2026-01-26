# frozen_string_literal: true

class JobStatus < ApplicationRecord
  validates :name, presence: true, uniqueness: true
end
