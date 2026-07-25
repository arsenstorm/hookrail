class AddHealthToConnections < ActiveRecord::Migration[8.1]
  def change
    add_column :connections, :consecutive_failures, :integer, default: 0, null: false
    add_column :connections, :unhealthy_since, :datetime
  end
end
