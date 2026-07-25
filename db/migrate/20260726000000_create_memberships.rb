class CreateMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :memberships do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false, default: "member"
      t.timestamps
    end
    add_index :memberships, %i[organization_id user_id], unique: true
    add_index :memberships, :organization_id, unique: true, where: "role = 'owner'",
              name: "idx_memberships_one_owner_per_org"

    # Existing orgs are single-user: their owner becomes the owner member.
    reversible do |dir|
      dir.up do
        execute <<~SQL
          INSERT INTO memberships (organization_id, user_id, role, created_at, updated_at)
          SELECT id, owner_id, 'owner', NOW(), NOW() FROM organizations
        SQL
      end
    end
  end
end
