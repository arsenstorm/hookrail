class AddMultiProjectSupport < ActiveRecord::Migration[8.1]
  def change
    # Remembered project per user+org; a deleted project nulls out and the
    # reader falls back to the first accessible project.
    add_column :memberships, :current_project_id, :bigint
    add_foreign_key :memberships, :projects, column: :current_project_id, on_delete: :nullify

    # Case-insensitive per-org name uniqueness; safe to add because every org
    # currently holds a single "Default" project.
    add_index :projects, "organization_id, lower(name)", unique: true, name: "index_projects_on_org_and_lower_name"
  end
end
