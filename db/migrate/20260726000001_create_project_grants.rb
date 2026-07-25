class CreateProjectGrants < ActiveRecord::Migration[8.1]
  def change
    create_table :project_grants do |t|
      t.references :membership, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: true
      t.string :level, null: false
      t.timestamps
    end
    add_index :project_grants, %i[membership_id project_id], unique: true
  end
end
