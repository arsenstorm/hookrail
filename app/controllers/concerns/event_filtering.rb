# Filter params shared by the events list and bulk retry: both must resolve
# "the current filtered view" to the same relation.
module EventFiltering
  # Relative presets for the time-range control. Anything else is a custom
  # from/to day range, which the two date fields still cover.
  RANGES = { "1h" => 1.hour, "24h" => 24.hours, "7d" => 7.days, "30d" => 30.days }.freeze

  private

  def set_event_filters
    @source_id = params[:source_id].presence
    @status    = params[:status].presence_in(Event::DELIVERY_STATUSES)
    @q         = params[:q].to_s.strip
    @range     = params[:range].presence_in(RANGES.keys)
    # A preset and an explicit range are the same control, so only one wins.
    @from      = @range ? "" : params[:from].to_s
    @to        = @range ? "" : params[:to].to_s
    @filters_active = @source_id || @status || @q.present? || @from.present? || @to.present? || @range
    @filter_params  = { source_id: @source_id, status: @status, q: @q.presence,
                        from: @from.presence, to: @to.presence, range: @range }.compact
  end

  # Project-scoped events matching the active filters; no order, includes, or cursor.
  def filtered_events
    scope = Event.joins(:source).where(sources: { project_id: Current.project.id })
    scope = scope.where(source_id: @source_id) if @source_id
    scope = scope.with_delivery_status(@status) if @status
    scope = scope.where("events.body ILIKE ?", "%#{Event.sanitize_sql_like(@q)}%") if @q.present?
    scope = scope.where("events.received_at >= ?", RANGES[@range].ago) if @range
    if (from_time = parse_from(@from)); scope = scope.where("events.received_at >= ?", from_time); end
    if (to_time = parse_to(@to));       scope = scope.where("events.received_at <= ?", to_time);   end
    scope
  end

  # What a bulk action operates on: the rows the operator ticked, or the whole
  # filtered set when the table sent none. `all_filtered` is how the "select all
  # matching" affordance opts back out of the selection still shown on screen.
  def selected_events
    ids = params[:event_ids]
    return filtered_events if params[:all_filtered].present? || !ids.is_a?(Array)

    filtered_events.where(id: ids)
  end

  # Inclusive lower bound. An ISO datetime (the picker always sends one, offset
  # included) is used exactly; a bare date widens to start-of-day.
  def parse_from(str)
    return nil if str.blank?
    time = Time.zone.parse(str)
    return nil unless time
    str.include?(":") ? time : time.beginning_of_day
  rescue ArgumentError
    nil
  end

  # Inclusive upper bound; a bare date widens to end-of-day.
  def parse_to(str)
    return nil if str.blank?
    time = Time.zone.parse(str)
    return nil unless time
    str.include?(":") ? time : time.end_of_day
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
