class CreateInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :invitations do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :email, null: false
      t.string :role, null: false, default: "member"
      t.jsonb :grants, null: false, default: []
      t.string :token, null: false
      t.timestamps
    end
    add_index :invitations, :token, unique: true
  end
end
