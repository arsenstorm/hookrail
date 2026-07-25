class AddRetryPolicyToConnections < ActiveRecord::Migration[8.1]
  def change
    add_column :connections, :retry_policy, :jsonb
  end
end
