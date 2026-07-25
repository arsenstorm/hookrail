class DashboardController < ApplicationController
  def show
    @unhealthy_connections = Current.project.connections.unhealthy.includes(:source, :destination)
  end
end
