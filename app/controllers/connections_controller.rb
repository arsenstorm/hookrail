class ConnectionsController < ApplicationController
  before_action :require_project_access
  before_action :require_project_editor, except: :index

  STATUS_NOTICES = {
    "active" => "Connection resumed.",
    "paused" => "Connection paused.",
    "disabled" => "Connection disabled."
  }.freeze

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
    load_preview_events
  end

  # The edit page edits the routing rule and the transformation; a connection's
  # endpoints are immutable after creation so attempt history always matches its route.
  def update
    @connection = Current.project.connections.includes(:source, :destination).find(params[:id])
    return render_preview if params[:preview].present?

    if @connection.update(routing_rule: routing_rule_params, transformation: transformation_param,
                          retry_policy: retry_policy_params)
      redirect_to connections_path, notice: "Connection updated."
    else
      load_preview_events
      render :edit, status: :unprocessable_entity
    end
  end

  def update_status
    @connection = Current.project.connections.find(params[:id])
    status = params.require(:status)
    return redirect_to connections_path, alert: "Unknown status." unless Connection.statuses.key?(status)

    @connection.update!(status: status)
    redirect_to connections_path, notice: STATUS_NOTICES.fetch(status)
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

  def transformation_param
    params.require(:connection)[:transformation]
  end

  # All three fields blank -> no policy (default schedule). Non-numeric input
  # is passed through untouched so the model's validation can name the problem.
  def retry_policy_params
    raw = params.require(:connection)
    values = [ raw[:retry_strategy], raw[:retry_interval], raw[:retry_max_attempts] ].map { |v| v.to_s.strip.presence }
    return nil if values.all?(&:nil?)

    strategy, interval, max_attempts = values
    {
      "strategy" => strategy,
      "interval" => Integer(interval, exception: false) || interval,
      "max_attempts" => Integer(max_attempts, exception: false) || max_attempts
    }
  end

  # Preview never saves: the submitted values are assigned so the re-rendered
  # form keeps them, then the code runs against one stored event.
  def render_preview
    @connection.assign_attributes(routing_rule: routing_rule_params, transformation: transformation_param,
                                  retry_policy: retry_policy_params)
    event = Event.joins(:source).where(sources: { project_id: Current.project.id })
                 .find_by(id: params[:preview_event_id])
    if @connection.transformation.blank?
      @preview_error = "No transformation code to preview."
    elsif event.nil?
      @preview_error = "Pick an event to preview against."
    else
      @preview = run_preview(@connection.transformation, event)
    end
    load_preview_events
    render :edit
  end

  def run_preview(code, event)
    Transformation::Runner.run(code, event)
  rescue Transformation::Error => e
    @preview_error = e.message
    nil
  end

  def load_preview_events
    @preview_events = @connection.source.events.order(received_at: :desc).limit(25)
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
