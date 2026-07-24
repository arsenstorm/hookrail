class CreateSources < ActiveRecord::Migration[8.1]
  def change
    create_table :sources do |t|
      t.string :name, null: false
      t.string :token, null: false

      t.timestamps
    end
    add_index :sources, :token, unique: true
  end
end
