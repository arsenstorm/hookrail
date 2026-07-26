module EventsHelper
  RANGE_LABELS = { "1h" => "Last hour", "24h" => "Last 24 hours",
                   "7d" => "Last 7 days", "30d" => "Last 30 days" }.freeze

  # What the time-range trigger says: a preset name, a formatted range, or the
  # open-ended default.
  def time_range_label(range, from, to)
    return RANGE_LABELS.fetch(range) if range.present?
    return "All time" if from.blank? && to.blank?
    return "From #{time_stamp(from)}" if to.blank?
    return "Until #{time_stamp(to)}" if from.blank?

    "#{time_stamp(from)} – #{time_stamp(to)}"
  rescue ArgumentError
    "Custom range"
  end

  # "Jul 26, 14:52" for a datetime (shown in the offset it was picked in, not
  # the server zone), "Jul 26" for a bare date from an old link.
  def time_stamp(str)
    time = begin
      Time.iso8601(str)
    rescue ArgumentError
      Time.zone.parse(str)
    end
    raise ArgumentError, str unless time
    time.strftime(str.include?(":") ? "%b %-d, %H:%M" : "%b %-d")
  end

  def delivery_summary(event)
    attempts = event.attempts.to_a
    return "no attempts" if attempts.empty?

    "#{attempts.count(&:succeeded?)}/#{attempts.size} delivered"
  end

  # Colour carries the same meaning as the text, never on its own: the ratio
  # is always spelled out beside it.
  def delivery_badge_classes(event)
    attempts = event.attempts.to_a
    return "#{ui(:badge)} #{ui(:badge_neutral)}" if attempts.empty?

    succeeded = attempts.count(&:succeeded?)
    tone = if succeeded == attempts.size then :badge_green
    elsif succeeded.zero? then :badge_red
    else :badge_amber
    end
    "#{ui(:badge)} #{ui(tone)}"
  end
end
