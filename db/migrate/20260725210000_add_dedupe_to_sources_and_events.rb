class AddDedupeToSourcesAndEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :sources, :dedupe, :jsonb, default: {}, null: false
    add_column :events, :dedupe_key, :string
    add_column :events, :duplicate, :boolean, default: false, null: false
    add_index :events, [ :source_id, :dedupe_key, :received_at ],
              where: "dedupe_key IS NOT NULL", name: "index_events_on_dedupe_lookup"
  end
end
