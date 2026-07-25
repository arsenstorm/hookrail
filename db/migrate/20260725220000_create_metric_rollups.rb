class CreateMetricRollups < ActiveRecord::Migration[8.1]
  def change
    create_table :metric_rollups do |t|
      t.bigint :project_id, null: false
      t.bigint :connection_id
      t.date :day, null: false
      t.integer :events_received, default: 0, null: false
      t.integer :delivered_count, default: 0, null: false
      t.integer :failed_count, default: 0, null: false
      t.integer :pending_count, default: 0, null: false
      t.timestamps
    end
    add_index :metric_rollups, [ :project_id, :day, :connection_id ], unique: true,
              where: "connection_id IS NOT NULL", name: "idx_metric_rollups_connection_day"
    add_index :metric_rollups, [ :project_id, :day ], unique: true,
              where: "connection_id IS NULL", name: "idx_metric_rollups_project_day"
  end
end
