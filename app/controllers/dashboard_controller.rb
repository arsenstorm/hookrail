class DashboardController < ApplicationController
  def show
    @unhealthy_connections = Current.project ? Current.project.connections.unhealthy.includes(:source, :destination) : Connection.none
  end
end
