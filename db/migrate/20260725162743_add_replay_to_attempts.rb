class AddReplayToAttempts < ActiveRecord::Migration[8.1]
  def change
    add_column :attempts, :replay, :boolean, default: false, null: false
  end
end
