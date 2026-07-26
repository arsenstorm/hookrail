class CreateCliAuthorizations < ActiveRecord::Migration[8.1]
  def change
    create_table :cli_authorizations do |t|
      t.string :device_code_digest, null: false
      t.string :user_code, null: false
      t.string :device_name, null: false
      t.string :status, null: false, default: "pending"
      t.references :user, null: true, foreign_key: true
      t.references :organization, null: true, foreign_key: true
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :cli_authorizations, :device_code_digest, unique: true
    add_index :cli_authorizations, :user_code, unique: true
  end
end
