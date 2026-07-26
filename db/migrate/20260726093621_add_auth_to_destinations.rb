class AddAuthToDestinations < ActiveRecord::Migration[8.1]
  def change
    add_column :destinations, :auth, :jsonb, default: {}, null: false
  end
end
