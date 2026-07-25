class AddRateLimitToDestinations < ActiveRecord::Migration[8.1]
  def change
    add_column :destinations, :rate_limit, :integer
    add_column :destinations, :rate_limit_period, :string
    add_column :destinations, :rate_window_started_at, :datetime
    add_column :destinations, :rate_window_count, :integer, default: 0, null: false
  end
end
