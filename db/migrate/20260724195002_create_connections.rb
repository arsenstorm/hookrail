class CreateConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :connections do |t|
      t.references :source, null: false, foreign_key: true
      t.references :destination, null: false, foreign_key: true
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :connections, [ :source_id, :destination_id ], unique: true
    add_index :connections, [ :source_id, :active ]
  end
end
