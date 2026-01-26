# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_01_26_163736) do
  create_table "job_statuses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "error"
    t.string "name", null: false
    t.datetime "ran_at"
    t.integer "sprints_failed"
    t.integer "sprints_succeeded"
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_job_statuses_on_name", unique: true
  end

  create_table "sprints", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "data"
    t.date "end_date", null: false
    t.date "start_date", null: false
    t.datetime "updated_at", null: false
    t.index ["start_date", "end_date"], name: "index_sprints_on_dates_unique", unique: true
    t.index ["start_date"], name: "index_sprints_on_start_date"
    t.index ["updated_at"], name: "index_sprints_on_updated_at"
  end
end
