class EventsController < ApplicationController
  PAGE_SIZE = 50

  def index
    @sources   = Current.project.sources.order(:name)
    @source_id = params[:source_id].presence
    @status    = params[:status].presence_in(Event::DELIVERY_STATUSES)
    @q         = params[:q].to_s.strip
    @from      = params[:from].to_s
    @to        = params[:to].to_s

    scope = Event
      .joins(:source)
      .where(sources: { project_id: Current.project.id })
      .includes(:source, :attempts)
      .order(received_at: :desc, id: :desc)

    scope = scope.where(source_id: @source_id) if @source_id
    scope = scope.with_delivery_status(@status) if @status
    scope = scope.where("events.body ILIKE ?", "%#{Event.sanitize_sql_like(@q)}%") if @q.present?

    if (from_time = parse_from(@from)); scope = scope.where("events.received_at >= ?", from_time); end
    if (to_time = parse_to(@to));       scope = scope.where("events.received_at <= ?", to_time);   end

    if (cursor = decode_cursor(params[:cursor]))
      scope = scope.before_cursor(cursor[:received_at], cursor[:id])
    end

    @filters_active = @source_id || @status || @q.present? || @from.present? || @to.present?
    @filter_params  = request.query_parameters.except("cursor")

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

  # Inclusive start-of-day in the app time zone; blank/garbage -> nil (bound absent).
  def parse_from(str)
    return nil if str.blank?
    Time.zone.parse(str)&.beginning_of_day
  rescue ArgumentError
    nil
  end

  # Inclusive end-of-day in the app time zone; blank/garbage -> nil (bound absent).
  def parse_to(str)
    return nil if str.blank?
    Time.zone.parse(str)&.end_of_day
  rescue ArgumentError
    nil
  end

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
