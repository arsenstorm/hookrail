class ConnectionsController < ApplicationController
  def index
    @connections = Current.project.connections.includes(:source, :destination).order(created_at: :desc)
  end

  def new
    @connection = Current.project.connections.new
    load_options
  end

  def create
    @connection = Current.project.connections.new(connection_params)
    if @connection.save
      redirect_to connections_path, notice: "Connection created."
    else
      load_options
      render :new, status: :unprocessable_entity
    end
  end

  def toggle
    @connection = Current.project.connections.find(params[:id])
    @connection.update!(active: !@connection.active)
    redirect_to connections_path,
      notice: (@connection.active ? "Connection activated." : "Connection deactivated.")
  end

  def destroy
    @connection = Current.project.connections.find(params[:id])
    @connection.destroy
    redirect_to connections_path, notice: "Connection deleted."
  end

  private

  def connection_params
    params.require(:connection).permit(:source_id, :destination_id)
  end

  def load_options
    @sources = Current.project.sources.order(:name)
    @destinations = Current.project.destinations.order(:name)
  end
end
