class AddRetentionDaysToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :retention_days, :integer, default: 30, null: false
  end
end
