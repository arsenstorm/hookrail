class CreateOrganizations < ActiveRecord::Migration[8.1]
  def change
    create_table :organizations do |t|
      t.string :name, null: false
      t.references :owner, null: false, index: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :organizations, :owner_id, unique: true
  end
end
