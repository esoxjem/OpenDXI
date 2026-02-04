# frozen_string_literal: true

class CreateTeams < ActiveRecord::Migration[8.1]
  def change
    create_table :teams do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :source, null: false, default: "custom"
      t.integer :github_team_id
      t.boolean :synced, null: false, default: true

      t.timestamps
    end

    add_index :teams, :slug, unique: true
    add_index :teams, :github_team_id, unique: true
  end
end
