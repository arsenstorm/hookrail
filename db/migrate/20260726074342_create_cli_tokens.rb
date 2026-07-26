class CreateCliTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :cli_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.string :token_digest, null: false
      t.string :prefix, null: false
      t.datetime :last_used_at
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :cli_tokens, :token_digest, unique: true
  end
end
