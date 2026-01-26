class ImproveSprintIndexes < ActiveRecord::Migration[7.1]
  def change
    # Add index for health endpoint query: Sprint.maximum(:updated_at)
    add_index :sprints, :updated_at

    # Remove duplicate unique index (keep index_sprints_on_dates_unique)
    remove_index :sprints, name: "index_sprints_on_start_date_and_end_date"
  end
end
