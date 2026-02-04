# frozen_string_literal: true

class CreateDevelopers < ActiveRecord::Migration[8.1]
  def change
    create_table :developers do |t|
      t.bigint :github_id, null: false
      t.string :github_login, null: false
      t.string :name
      t.string :avatar_url
      t.boolean :visible, null: false, default: true
      t.string :source, null: false, default: "org_member"

      t.timestamps
    end

    add_index :developers, :github_id, unique: true
    add_index :developers, :github_login, unique: true
    add_index :developers, :visible
  end
end
