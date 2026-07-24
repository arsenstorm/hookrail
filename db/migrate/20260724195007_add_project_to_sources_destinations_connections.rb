class AddProjectToSourcesDestinationsConnections < ActiveRecord::Migration[8.1]
  def change
    add_reference :sources, :project, null: false, foreign_key: true
    add_reference :destinations, :project, null: false, foreign_key: true
    add_reference :connections, :project, null: false, foreign_key: true
  end
end
