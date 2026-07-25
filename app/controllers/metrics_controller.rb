class MetricsController < ApplicationController
  before_action :require_project_access

  # Each sort key orders worst-offender-first for its column.
  SORTS = {
    "failed" => ->(row) { [ -row[:failed], -row[:events] ] },
    "events" => ->(row) { -row[:events] },
    "success" => ->(row) { [ row[:success_rate] || 101.0, -row[:events] ] }
  }.freeze

  def show
    @metrics = Metrics.new(project: Current.project, window: params[:window])
    @sort = SORTS.key?(params[:sort]) ? params[:sort] : "failed"
    @connection_rows = @metrics.by_connection.sort_by(&SORTS[@sort])
  end
end
