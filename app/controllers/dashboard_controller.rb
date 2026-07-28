class DashboardController < ApplicationController
  # Each sort key orders worst-offender-first for its column.
  SORTS = {
    "failed" => ->(row) { [ -row[:failed], -row[:events] ] },
    "events" => ->(row) { -row[:events] },
    "success" => ->(row) { [ row[:success_rate] || 101.0, -row[:events] ] }
  }.freeze

  def show
    @unhealthy_connections = Current.project ? Current.project.connections.actively_unhealthy.includes(:source, :destination) : Connection.none
    return unless Current.project

    @metrics = Metrics.new(project: Current.project, window: params[:window])
    @totals = @metrics.totals
    @sort = SORTS.key?(params[:sort]) ? params[:sort] : "failed"
    @connection_rows = @metrics.by_connection.sort_by(&SORTS[@sort])
    @open_issues_count = Current.project.issues.unresolved.count
    @recent_events = Event.joins(:source).where(sources: { project_id: Current.project.id })
                          .includes(:source).order(received_at: :desc).limit(6)
  end
end
