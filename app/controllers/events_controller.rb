class EventsController < ApplicationController
  def index
    @events = Event
      .joins(:source)
      .where(sources: { project_id: Current.project.id })
      .includes(:source, :attempts)
      .order(received_at: :desc)
      .limit(100)
  end

  def show
    @event = Event
      .joins(:source)
      .where(sources: { project_id: Current.project.id })
      .includes(attempts: { connection: [ :source, :destination ] })
      .find(params[:id])

    # Latest attempt per connection that ended dead/failed is retryable (Slice 5).
    @retryable_attempt_ids = @event.attempts
      .group_by(&:connection_id)
      .values
      .map { |attempts| attempts.max_by(&:attempt_number) }
      .select { |latest| latest.dead? || latest.failed? }
      .map(&:id)
      .to_set
  end
end
