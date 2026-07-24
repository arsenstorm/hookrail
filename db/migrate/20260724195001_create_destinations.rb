class CreateDestinations < ActiveRecord::Migration[8.1]
  def change
    create_table :destinations do |t|
      t.string :name, null: false
      t.string :url, null: false
      t.jsonb :headers, null: false, default: {}
      t.string :signing_secret, null: false
      t.timestamps
    end
    add_index :destinations, :signing_secret, unique: true
  end
end
