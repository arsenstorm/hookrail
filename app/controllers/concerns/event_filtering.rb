# Filter params shared by the events list and bulk retry: both must resolve
# "the current filtered view" to the same relation.
module EventFiltering
  private

  def set_event_filters
    @source_id = params[:source_id].presence
    @status    = params[:status].presence_in(Event::DELIVERY_STATUSES)
    @q         = params[:q].to_s.strip
    @from      = params[:from].to_s
    @to        = params[:to].to_s
    @filters_active = @source_id || @status || @q.present? || @from.present? || @to.present?
    @filter_params  = { source_id: @source_id, status: @status, q: @q.presence,
                        from: @from.presence, to: @to.presence }.compact
  end

  # Project-scoped events matching the active filters; no order, includes, or cursor.
  def filtered_events
    scope = Event.joins(:source).where(sources: { project_id: Current.project.id })
    scope = scope.where(source_id: @source_id) if @source_id
    scope = scope.with_delivery_status(@status) if @status
    scope = scope.where("events.body ILIKE ?", "%#{Event.sanitize_sql_like(@q)}%") if @q.present?
    if (from_time = parse_from(@from)); scope = scope.where("events.received_at >= ?", from_time); end
    if (to_time = parse_to(@to));       scope = scope.where("events.received_at <= ?", to_time);   end
    scope
  end

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
end
