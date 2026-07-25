class RetriesController < ApplicationController
  def create
    event = scoped_events.find(params[:event_id])
    connection = event.source.connections.find(params[:connection_id])

    latest = Attempt.where(event: event, connection: connection).order(:attempt_number).last
    unless latest && (latest.dead? || latest.failed?)
      return redirect_to event_path(event), alert: "That delivery can't be retried."
    end

    # Synchronously claim the delivery slot so a double-click can't enqueue twice (Slice 5 R5):
    # the new :pending attempt makes the pair's latest status non-retryable until the job runs.
    number = Attempt.where(event: event, connection: connection).maximum(:attempt_number).to_i + 1
    Attempt.create!(event: event, connection: connection, attempt_number: number,
                    status: :pending, attempted_at: Time.current)
    DeliverEventJob.perform_later(event.id, connection.id)

    redirect_to event_path(event), notice: "Retrying delivery."
  rescue ActiveRecord::RecordNotUnique
    # Lost the claim race to a concurrent retry; the other request enqueued the job.
    redirect_to event_path(event), notice: "Retrying delivery."
  end

  private

  def scoped_events
    Event.joins(:source).where(sources: { project_id: Current.project.id })
  end
end
