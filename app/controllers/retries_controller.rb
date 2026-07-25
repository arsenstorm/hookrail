class RetriesController < ApplicationController
  before_action :require_project_editor

  def create
    event = scoped_events.find(params[:event_id])
    connection = event.source.connections.find(params[:connection_id])

    unless connection.status_active?
      return redirect_to event_path(event), alert: "That connection is #{connection.status} — deliveries are stopped."
    end

    latest = Attempt.where(event: event, connection: connection).order(:attempt_number).last
    unless latest && (latest.dead? || latest.failed?)
      return redirect_to event_path(event), alert: "That delivery can't be retried."
    end

    Attempt.claim_retry!(event_id: event.id, connection_id: connection.id)

    redirect_to event_path(event), notice: "Retrying delivery."
  end

  private

  def scoped_events
    Event.joins(:source).where(sources: { project_id: Current.project.id })
  end
end
