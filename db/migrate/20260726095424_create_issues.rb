class CreateIssues < ActiveRecord::Migration[8.1]
  def change
    create_table :issues do |t|
      t.references :project, null: false, foreign_key: true
      t.references :subject, polymorphic: true, null: false
      t.string :issue_type, null: false
      t.string :status, null: false, default: "open"
      t.integer :count, null: false, default: 1
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.string :summary
      t.timestamps
    end
    # One non-resolved issue per (type, subject); arbitrates the concurrent-create race.
    add_index :issues, [ :issue_type, :subject_type, :subject_id ],
              unique: true, where: "status != 'resolved'", name: "index_issues_unresolved_uniqueness"
    add_index :issues, [ :project_id, :status, :last_seen_at ]

    add_column :organizations, :slack_webhook_url, :string
    add_column :organizations, :discord_webhook_url, :string
  end
end
