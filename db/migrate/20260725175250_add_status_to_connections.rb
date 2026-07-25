class AddStatusToConnections < ActiveRecord::Migration[8.1]
  def up
    add_column :connections, :status, :string, null: false, default: "active"
    add_index :connections, [ :source_id, :status ]
    # Connections deactivated via the legacy boolean become disabled.
    execute "UPDATE connections SET status = 'disabled' WHERE active = false"
  end

  def down
    remove_index :connections, [ :source_id, :status ]
    remove_column :connections, :status
  end
end
