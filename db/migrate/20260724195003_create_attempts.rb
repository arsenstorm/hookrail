class CreateAttempts < ActiveRecord::Migration[8.1]
  def change
    create_table :attempts do |t|
      t.references :event, null: false, foreign_key: true
      t.references :connection, null: false, foreign_key: true
      t.integer :attempt_number, null: false
      t.string :status, null: false, default: "pending"
      t.integer :response_status
      t.text :response_body
      t.text :error
      t.integer :duration_ms
      t.datetime :attempted_at, null: false
      t.timestamps
    end
    add_index :attempts, [ :event_id, :connection_id, :attempt_number ], unique: true, name: "idx_attempts_on_event_connection_number"
  end
end
