class ConnectionsController < ApplicationController
  def index
    @connections = Current.project.connections.includes(:source, :destination).order(created_at: :desc)
    @unhealthy_connections = Current.project.connections.unhealthy.includes(:source, :destination)
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

  def edit
    @connection = Current.project.connections.includes(:source, :destination).find(params[:id])
  end

  # The edit page edits ONLY the routing rule; a connection's endpoints are
  # immutable after creation so attempt history always matches its route.
  def update
    @connection = Current.project.connections.find(params[:id])
    if @connection.update(routing_rule: routing_rule_params)
      redirect_to connections_path, notice: "Routing rule updated."
    else
      @connection = Current.project.connections.includes(:source, :destination).find(params[:id])
      render :edit, status: :unprocessable_entity
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

  def routing_rule_params
    raw = params.require(:connection)
    {
      "path" => raw[:rule_path].to_s.strip,
      "http_method" => raw[:rule_http_method].to_s.strip,
      "headers" => parse_kv_lines(raw[:rule_headers_text], ":"),
      "body" => parse_kv_lines(raw[:rule_body_text], "=")
    }.compact_blank
  end

  # One criterion per line, split on the first separator; blank/keyless lines dropped.
  def parse_kv_lines(text, separator)
    text.to_s.lines.each_with_object({}) do |line, acc|
      key, sep, value = line.partition(separator)
      next if sep.empty?

      key = key.strip
      acc[key] = value.strip unless key.empty?
    end
  end

  def load_options
    @sources = Current.project.sources.order(:name)
    @destinations = Current.project.destinations.order(:name)
  end
end
