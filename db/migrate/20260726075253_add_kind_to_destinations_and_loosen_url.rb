class AddKindToDestinationsAndLoosenUrl < ActiveRecord::Migration[8.1]
  def change
    add_column :destinations, :kind, :string, null: false, default: "http"
    change_column_null :destinations, :url, true
  end
end
