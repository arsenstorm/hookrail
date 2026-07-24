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

ActiveRecord::Schema[8.1].define(version: 2026_07_24_195007) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "attempts", force: :cascade do |t|
    t.integer "attempt_number", null: false
    t.datetime "attempted_at", null: false
    t.bigint "connection_id", null: false
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.text "error"
    t.bigint "event_id", null: false
    t.text "response_body"
    t.integer "response_status"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["connection_id"], name: "index_attempts_on_connection_id"
    t.index ["event_id", "connection_id", "attempt_number"], name: "idx_attempts_on_event_connection_number", unique: true
    t.index ["event_id"], name: "index_attempts_on_event_id"
  end

  create_table "connections", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.bigint "destination_id", null: false
    t.bigint "project_id", null: false
    t.bigint "source_id", null: false
    t.datetime "updated_at", null: false
    t.index ["destination_id"], name: "index_connections_on_destination_id"
    t.index ["project_id"], name: "index_connections_on_project_id"
    t.index ["source_id", "active"], name: "index_connections_on_source_id_and_active"
    t.index ["source_id", "destination_id"], name: "index_connections_on_source_id_and_destination_id", unique: true
    t.index ["source_id"], name: "index_connections_on_source_id"
  end

  create_table "destinations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "headers", default: {}, null: false
    t.string "name", null: false
    t.bigint "project_id", null: false
    t.string "signing_secret", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["project_id"], name: "index_destinations_on_project_id"
    t.index ["signing_secret"], name: "index_destinations_on_signing_secret", unique: true
  end

  create_table "events", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.jsonb "headers", default: {}, null: false
    t.string "http_method", null: false
    t.string "path"
    t.string "query_string"
    t.datetime "received_at", null: false
    t.bigint "source_id", null: false
    t.datetime "updated_at", null: false
    t.index ["source_id", "received_at"], name: "index_events_on_source_id_and_received_at"
    t.index ["source_id"], name: "index_events_on_source_id"
  end

  create_table "organizations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "owner_id", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_id"], name: "index_organizations_on_owner_id", unique: true
  end

  create_table "projects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_projects_on_organization_id"
  end

  create_table "sources", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "project_id", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_sources_on_project_id"
    t.index ["token"], name: "index_sources_on_token", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.string "email"
    t.string "github_login"
    t.string "github_uid", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["github_uid"], name: "index_users_on_github_uid", unique: true
  end

  add_foreign_key "attempts", "connections"
  add_foreign_key "attempts", "events"
  add_foreign_key "connections", "destinations"
  add_foreign_key "connections", "projects"
  add_foreign_key "connections", "sources"
  add_foreign_key "destinations", "projects"
  add_foreign_key "events", "sources"
  add_foreign_key "organizations", "users", column: "owner_id"
  add_foreign_key "projects", "organizations"
  add_foreign_key "sources", "projects"
end
