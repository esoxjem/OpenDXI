class CreateSprints < ActiveRecord::Migration[8.1]
  def change
    create_table :sprints do |t|
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.json :data

      t.timestamps
    end

    add_index :sprints, [ :start_date, :end_date ], unique: true
    add_index :sprints, :start_date
  end
end
