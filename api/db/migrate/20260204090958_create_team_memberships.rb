# frozen_string_literal: true

class CreateTeamMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :team_memberships do |t|
      t.references :developer, null: false
      t.references :team, null: false

      t.timestamps
    end

    add_index :team_memberships, [:team_id, :developer_id], unique: true,
              name: "index_team_memberships_on_team_and_developer"
  end
end
