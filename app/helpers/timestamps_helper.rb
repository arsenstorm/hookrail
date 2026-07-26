module TimestampsHelper
  DAY_SECONDS = 86_400

  # Every user-facing timestamp in the app renders through here, so there is
  # one convention rather than a dozen strftime strings: relative while the
  # moment is recent, an absolute date once it is a day old.
  #
  # The relative buckets read identically in every zone, so the server can
  # compute them and the value is already right with JS off, before hydration,
  # and in tests. Only the >=24h date is zone-sensitive; it goes out as UTC and
  # the timestamp controller rewrites it (and builds the hover card) for the
  # viewer's zone.
  #
  # Pass tabindex: nil when wrapping the tag in a link — the link is already
  # the focus stop and the controller finds it, so a second one would only add
  # a dead tab stop per table row.
  def timestamp_tag(time, **attrs)
    tag.time(timestamp_text(time), datetime: time.utc.iso8601, tabindex: "0",
             data: { controller: "timestamp" }, **attrs,
             class: token_list("tabular-nums whitespace-nowrap", attrs[:class]))
  end

  # The bare string, for the places that can't hold markup (aria-labels).
  def timestamp_text(time, now: Time.current)
    seconds = (now - time).to_i
    case seconds
    when ..0          then "Just now"
    when 1...60       then "#{seconds}s ago"
    when 60...3600    then "#{seconds / 60}m ago"
    when 3600...DAY_SECONDS then "#{seconds / 3600}h ago"
    else timestamp_date(time.utc, now.utc)
    end
  end

  # "May 30" this year, "Dec 12, 2024" before it — the year only earns its
  # space once it stops being the obvious one.
  def timestamp_date(utc, now = Time.now.utc)
    utc.strftime(utc.year == now.year ? "%b %-d" : "%b %-d, %Y")
  end
end
