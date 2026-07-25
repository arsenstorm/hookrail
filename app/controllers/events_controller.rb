class EventsController < ApplicationController
  include EventFiltering

  PAGE_SIZE = 50

  def index
    @sources = Current.project.sources.order(:name)
    set_event_filters

    scope = filtered_events.includes(:source, :attempts).order(received_at: :desc, id: :desc)

    if (cursor = decode_cursor(params[:cursor]))
      scope = scope.before_cursor(cursor[:received_at], cursor[:id])
    end

    @retryable_count = Attempt.retryable_for(filtered_events).count
    @filtered_count  = filtered_events.count
    @connections     = Current.project.connections.includes(:source, :destination).order(created_at: :desc)

    rows         = scope.limit(PAGE_SIZE + 1).to_a
    @has_next    = rows.size > PAGE_SIZE
    @events      = rows.first(PAGE_SIZE)
    @next_cursor = @has_next ? encode_cursor(@events.last) : nil
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
      .select { |latest| (latest.dead? || latest.failed?) && latest.connection.status_active? }
      .map(&:id)
      .to_set
  end
end
