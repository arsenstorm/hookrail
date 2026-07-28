class BulkReplaysController < ApplicationController
  include EventFiltering

  before_action :require_project_editor

  # ponytail: enqueues in-request like bulk retry; move to a background job
  # if filtered sets grow past a few thousand events.
  def create
    set_event_filters
    connection = Current.project.connections.find(params[:connection_id])

    unless connection.status_active?
      return redirect_to events_path(@filter_params),
        alert: "That connection is #{connection.status}. Resume it before replaying."
    end

    events    = selected_events
    in_flight = Attempt.in_flight_event_ids(events, connection)
    enqueued  = 0
    events.find_each do |event|
      next if in_flight.include?(event.id)
      next unless connection.routes?(event)

      enqueued += 1 if Attempt.claim_retry!(event_id: event.id, connection_id: connection.id, replay: true)
    end
    redirect_to events_path(@filter_params), notice: "Replaying #{enqueued} #{"event".pluralize(enqueued)}."
  end
end
