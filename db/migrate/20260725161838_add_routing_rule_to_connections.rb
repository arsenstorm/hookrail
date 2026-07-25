class AddRoutingRuleToConnections < ActiveRecord::Migration[8.1]
  def change
    add_column :connections, :routing_rule, :jsonb, default: {}, null: false
  end
end
