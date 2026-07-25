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
      .select { |latest| latest.dead? || latest.failed? }
      .map(&:id)
      .to_set
  end

  private

  # Opaque cursor: urlsafe Base64 of "received_at_iso8601(6)|id".
  def encode_cursor(event)
    Base64.urlsafe_encode64("#{event.received_at.iso8601(6)}|#{event.id}")
  end

  # Decode cursor; blank/garbage -> nil (treated as no cursor, page 1).
  def decode_cursor(token)
    return nil if token.blank?
    raw = Base64.urlsafe_decode64(token)
    ts, id = raw.split("|", 2)
    time = Time.zone.parse(ts)
    return nil unless time && id.present?
    { received_at: time, id: id.to_i }
  rescue ArgumentError
    nil
  end
end
