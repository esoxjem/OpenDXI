class CreateJobStatuses < ActiveRecord::Migration[8.1]
  def change
    create_table :job_statuses do |t|
      t.string :name, null: false, index: { unique: true }
      t.string :status, null: false
      t.datetime :ran_at
      t.string :error
      t.integer :sprints_succeeded
      t.integer :sprints_failed

      t.timestamps
    end
  end
end
