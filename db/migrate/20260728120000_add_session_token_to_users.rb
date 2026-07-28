class AddSessionTokenToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :session_token, :string
    # Backfill before the NOT NULL so existing rows are valid; every current
    # cookie carries no token and is therefore signed out by this deploy.
    User.reset_column_information
    User.where(session_token: nil).find_each { |user| user.update_columns(session_token: SecureRandom.hex(16)) }
    change_column_null :users, :session_token, false
  end

  def down
    remove_column :users, :session_token
  end
end
