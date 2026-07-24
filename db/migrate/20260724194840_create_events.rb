class CreateEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :events do |t|
      t.references :source, null: false, foreign_key: true
      t.string :http_method, null: false
      t.string :path
      t.string :query_string
      t.jsonb :headers, null: false, default: {}
      t.text :body
      t.datetime :received_at, null: false

      t.timestamps
    end
    add_index :events, [ :source_id, :received_at ]
  end
end
