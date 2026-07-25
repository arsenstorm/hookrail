class RelaxOrganizationsOwnerIndex < ActiveRecord::Migration[8.1]
  # Ownership transfer lets one user own their personal org and a transferred
  # org at once, so owner_id can no longer be unique.
  def change
    remove_index :organizations, :owner_id
    add_index :organizations, :owner_id
  end
end
