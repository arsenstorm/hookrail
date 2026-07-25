class AddTransformationSupport < ActiveRecord::Migration[8.1]
  def change
    add_column :connections, :transformation, :text
    add_column :attempts, :transformed_headers, :jsonb
    add_column :attempts, :transformed_body, :text
  end
end
