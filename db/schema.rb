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

ActiveRecord::Schema[8.1].define(version: 2026_07_26_100000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "api_keys", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.string "prefix", null: false
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_api_keys_on_organization_id"
    t.index ["token_digest"], name: "index_api_keys_on_token_digest", unique: true
  end

  create_table "attempts", force: :cascade do |t|
    t.integer "attempt_number", null: false
    t.datetime "attempted_at", null: false
    t.bigint "connection_id", null: false
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.text "error"
    t.bigint "event_id", null: false
    t.boolean "replay", default: false, null: false
    t.text "response_body"
    t.integer "response_status"
    t.string "status", default: "pending", null: false
    t.text "transformed_body"
    t.jsonb "transformed_headers"
    t.datetime "updated_at", null: false
    t.index ["connection_id"], name: "index_attempts_on_connection_id"
    t.index ["event_id", "connection_id", "attempt_number"], name: "idx_attempts_on_event_connection_number", unique: true
    t.index ["event_id"], name: "index_attempts_on_event_id"
  end

  create_table "cli_authorizations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "device_code_digest", null: false
    t.string "device_name", null: false
    t.datetime "expires_at", null: false
    t.bigint "organization_id"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.string "user_code", null: false
    t.bigint "user_id"
    t.index ["device_code_digest"], name: "index_cli_authorizations_on_device_code_digest", unique: true
    t.index ["organization_id"], name: "index_cli_authorizations_on_organization_id"
    t.index ["user_code"], name: "index_cli_authorizations_on_user_code", unique: true
    t.index ["user_id"], name: "index_cli_authorizations_on_user_id"
  end

  create_table "cli_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_used_at"
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.string "prefix", null: false
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["organization_id"], name: "index_cli_tokens_on_organization_id"
    t.index ["token_digest"], name: "index_cli_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_cli_tokens_on_user_id"
  end

  create_table "connections", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "consecutive_failures", default: 0, null: false
    t.datetime "created_at", null: false
    t.bigint "destination_id", null: false
    t.bigint "project_id", null: false
    t.jsonb "retry_policy"
    t.jsonb "routing_rule", default: {}, null: false
    t.bigint "source_id", null: false
    t.string "status", default: "active", null: false
    t.text "transformation"
    t.datetime "unhealthy_since"
    t.datetime "updated_at", null: false
    t.index ["destination_id"], name: "index_connections_on_destination_id"
    t.index ["project_id"], name: "index_connections_on_project_id"
    t.index ["source_id", "active"], name: "index_connections_on_source_id_and_active"
    t.index ["source_id", "destination_id"], name: "index_connections_on_source_id_and_destination_id", unique: true
    t.index ["source_id", "status"], name: "index_connections_on_source_id_and_status"
    t.index ["source_id"], name: "index_connections_on_source_id"
  end

  create_table "destinations", force: :cascade do |t|
    t.jsonb "auth", default: {}, null: false
    t.datetime "created_at", null: false
    t.jsonb "headers", default: {}, null: false
    t.string "kind", default: "http", null: false
    t.string "name", null: false
    t.bigint "project_id", null: false
    t.integer "rate_limit"
    t.string "rate_limit_period"
    t.integer "rate_window_count", default: 0, null: false
    t.datetime "rate_window_started_at"
    t.string "signing_secret", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["project_id"], name: "index_destinations_on_project_id"
    t.index ["signing_secret"], name: "index_destinations_on_signing_secret", unique: true
  end

  create_table "events", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "dedupe_key"
    t.boolean "duplicate", default: false, null: false
    t.jsonb "headers", default: {}, null: false
    t.string "http_method", null: false
    t.string "path"
    t.string "query_string"
    t.datetime "received_at", null: false
    t.bigint "source_id", null: false
    t.datetime "updated_at", null: false
    t.index ["source_id", "dedupe_key", "received_at"], name: "index_events_on_dedupe_lookup", where: "(dedupe_key IS NOT NULL)"
    t.index ["source_id", "received_at"], name: "index_events_on_source_id_and_received_at"
    t.index ["source_id"], name: "index_events_on_source_id"
  end

  create_table "invitations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.jsonb "grants", default: [], null: false
    t.bigint "organization_id", null: false
    t.string "role", default: "member", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_invitations_on_organization_id"
    t.index ["token"], name: "index_invitations_on_token", unique: true
  end

  create_table "issues", force: :cascade do |t|
    t.integer "count", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "first_seen_at", null: false
    t.string "issue_type", null: false
    t.datetime "last_seen_at", null: false
    t.bigint "project_id", null: false
    t.string "status", default: "open", null: false
    t.bigint "subject_id", null: false
    t.string "subject_type", null: false
    t.string "summary"
    t.datetime "updated_at", null: false
    t.index ["issue_type", "subject_type", "subject_id"], name: "index_issues_unresolved_uniqueness", unique: true, where: "((status)::text <> 'resolved'::text)"
    t.index ["project_id", "status", "last_seen_at"], name: "index_issues_on_project_id_and_status_and_last_seen_at"
    t.index ["project_id"], name: "index_issues_on_project_id"
    t.index ["subject_type", "subject_id"], name: "index_issues_on_subject"
  end

  create_table "memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "current_project_id"
    t.bigint "organization_id", null: false
    t.string "role", default: "member", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["organization_id", "user_id"], name: "index_memberships_on_organization_id_and_user_id", unique: true
    t.index ["organization_id"], name: "idx_memberships_one_owner_per_org", unique: true, where: "((role)::text = 'owner'::text)"
    t.index ["organization_id"], name: "index_memberships_on_organization_id"
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "metric_rollups", force: :cascade do |t|
    t.bigint "connection_id"
    t.datetime "created_at", null: false
    t.date "day", null: false
    t.integer "delivered_count", default: 0, null: false
    t.integer "events_received", default: 0, null: false
    t.integer "failed_count", default: 0, null: false
    t.integer "pending_count", default: 0, null: false
    t.bigint "project_id", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "day", "connection_id"], name: "idx_metric_rollups_connection_day", unique: true, where: "(connection_id IS NOT NULL)"
    t.index ["project_id", "day"], name: "idx_metric_rollups_project_day", unique: true, where: "(connection_id IS NULL)"
  end

  create_table "organizations", force: :cascade do |t|
    t.string "alert_webhook_secret"
    t.string "alert_webhook_url"
    t.datetime "created_at", null: false
    t.string "discord_webhook_url"
    t.string "name", null: false
    t.bigint "owner_id", null: false
    t.integer "retention_days", default: 30, null: false
    t.string "slack_webhook_url"
    t.datetime "updated_at", null: false
    t.index ["owner_id"], name: "index_organizations_on_owner_id"
  end

  create_table "project_grants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "level", null: false
    t.bigint "membership_id", null: false
    t.bigint "project_id", null: false
    t.datetime "updated_at", null: false
    t.index ["membership_id", "project_id"], name: "index_project_grants_on_membership_id_and_project_id", unique: true
    t.index ["membership_id"], name: "index_project_grants_on_membership_id"
    t.index ["project_id"], name: "index_project_grants_on_project_id"
  end

  create_table "projects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.datetime "updated_at", null: false
    t.index "organization_id, lower((name)::text)", name: "index_projects_on_org_and_lower_name", unique: true
    t.index ["organization_id"], name: "index_projects_on_organization_id"
  end

  create_table "quarantined_webhooks", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.jsonb "headers", default: {}, null: false
    t.string "http_method", null: false
    t.string "path"
    t.string "query_string"
    t.string "reason", null: false
    t.datetime "received_at", null: false
    t.bigint "source_id", null: false
    t.datetime "updated_at", null: false
    t.index ["source_id", "received_at"], name: "index_quarantined_webhooks_on_source_id_and_received_at"
    t.index ["source_id"], name: "index_quarantined_webhooks_on_source_id"
  end

  create_table "solid_cable_messages", force: :cascade do |t|
    t.binary "channel", null: false
    t.bigint "channel_hash", null: false
    t.datetime "created_at", null: false
    t.binary "payload", null: false
    t.index ["channel"], name: "index_solid_cable_messages_on_channel"
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.integer "byte_size", null: false
    t.datetime "created_at", null: false
    t.binary "key", null: false
    t.bigint "key_hash", null: false
    t.binary "value", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "sources", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "dedupe", default: {}, null: false
    t.string "name", null: false
    t.bigint "project_id", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.jsonb "verification", default: {}, null: false
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

  add_foreign_key "api_keys", "organizations"
  add_foreign_key "attempts", "connections"
  add_foreign_key "attempts", "events"
  add_foreign_key "cli_authorizations", "organizations"
  add_foreign_key "cli_authorizations", "users"
  add_foreign_key "cli_tokens", "organizations"
  add_foreign_key "cli_tokens", "users"
  add_foreign_key "connections", "destinations"
  add_foreign_key "connections", "projects"
  add_foreign_key "connections", "sources"
  add_foreign_key "destinations", "projects"
  add_foreign_key "events", "sources"
  add_foreign_key "invitations", "organizations"
  add_foreign_key "issues", "projects"
  add_foreign_key "memberships", "organizations"
  add_foreign_key "memberships", "projects", column: "current_project_id", on_delete: :nullify
  add_foreign_key "memberships", "users"
  add_foreign_key "organizations", "users", column: "owner_id"
  add_foreign_key "project_grants", "memberships"
  add_foreign_key "project_grants", "projects"
  add_foreign_key "projects", "organizations"
  add_foreign_key "quarantined_webhooks", "sources"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "sources", "projects"
end
