class CreateApiKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :api_keys do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.string :token_digest, null: false, index: { unique: true }
      t.string :prefix, null: false
      t.datetime :revoked_at
      t.timestamps
    end
  end
end
