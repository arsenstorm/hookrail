class AddVerificationToSourcesAndCreateQuarantinedWebhooks < ActiveRecord::Migration[8.1]
  def change
    add_column :sources, :verification, :jsonb, default: {}, null: false

    create_table :quarantined_webhooks do |t|
      t.references :source, null: false, foreign_key: true
      t.string :http_method, null: false
      t.string :path
      t.string :query_string
      t.jsonb :headers, default: {}, null: false
      t.text :body
      t.string :reason, null: false
      t.datetime :received_at, null: false
      t.timestamps
    end
    add_index :quarantined_webhooks, [ :source_id, :received_at ]
  end
end
