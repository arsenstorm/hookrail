# Aggregated delivery health for one project over a window ("24h", "7d", "30d").
#
# A delivery is one (event, connection) pair; its state is the latest attempt's
# status: succeeded -> delivered, failed/dead -> failed, pending/delivering/held
# -> pending. Deliveries anchor to when the event was received, so a delivery
# never moves between buckets as it retries.
#
# Complete past days are read from metric_rollups (they survive retention
# pruning); today and the whole 24h window are computed live from raw rows.
# Latency percentiles always come from raw attempts, so they cover only what
# retention keeps.
class Metrics
  WINDOWS = %w[24h 7d 30d].freeze
  DAYS = { "7d" => 7, "30d" => 30 }.freeze
  DELIVERED = %w[succeeded].freeze
  FAILED = %w[failed dead].freeze

  attr_reader :project, :window

  def initialize(project:, window:)
    @project = project
    @window = WINDOWS.include?(window) ? window : "24h"
  end

  def self.state_for(status)
    return :delivered if DELIVERED.include?(status)
    return :failed if FAILED.include?(status)

    :pending
  end

  # Latest-attempt state counts per connection for events received in range:
  # {connection_id => {delivered:, failed:, pending:}}. Unscoped when project
  # is nil (rollup builds); project-scoped for live reads.
  def self.delivery_counts(range, project: nil)
    sub = Attempt.joins(:event).where(events: { received_at: range })
    sub = sub.joins(:connection).where(connections: { project_id: project.id }) if project
    sub = sub.select("DISTINCT ON (attempts.event_id, attempts.connection_id) attempts.connection_id, attempts.status")
             .order("attempts.event_id, attempts.connection_id, attempts.attempt_number DESC")
    Attempt.from(sub, :latest).group("latest.connection_id", "latest.status").count
           .each_with_object(Hash.new { |h, k| h[k] = { delivered: 0, failed: 0, pending: 0 } }) do |((cid, status), n), acc|
      acc[cid][state_for(status)] += n
    end
  end

  def totals
    @totals ||= begin
      t = { events_received: 0, delivered: 0, failed: 0, pending: 0 }
      buckets.each do |b|
        t[:events_received] += b[:events]
        t[:delivered] += b[:delivered]
        t[:failed] += b[:failed]
        t[:pending] += b[:pending]
      end
      t.merge(success_rate: success_rate(t[:delivered], t[:failed]))
    end
  end

  # Chart buckets oldest-first: hourly over 24h, daily over 7d/30d.
  # [{label:, events:, delivered:, failed:, pending:}]
  def buckets
    @buckets ||= window == "24h" ? hourly_buckets : daily_buckets
  end

  # Unsorted per-connection rows; the caller applies its own sort.
  # [{connection:, events:, delivered:, failed:, pending:, success_rate:}]
  def by_connection
    @by_connection ||= begin
      acc = Hash.new { |h, k| h[k] = { delivered: 0, failed: 0, pending: 0 } }
      if window == "24h"
        self.class.delivery_counts(window_start.., project: project).each { |cid, counts| acc[cid] = counts }
      else
        rollups.where.not(connection_id: nil).group(:connection_id)
               .pluck(:connection_id, Arel.sql("SUM(delivered_count)"),
                      Arel.sql("SUM(failed_count)"), Arel.sql("SUM(pending_count)"))
               .each { |cid, d, f, p| acc[cid] = { delivered: d, failed: f, pending: p } }
        self.class.delivery_counts(Date.current.all_day, project: project).each do |cid, counts|
          counts.each { |state, n| acc[cid][state] += n }
        end
      end
      connections = project.connections.where(id: acc.keys).includes(:source, :destination).index_by(&:id)
      acc.filter_map do |cid, counts|
        connection = connections[cid]
        next unless connection # rollups may outlive a deleted connection

        { connection: connection, events: counts.values.sum,
          success_rate: success_rate(counts[:delivered], counts[:failed]), **counts }
      end
    end
  end

  # [{destination:, count:, p50:, p95:}], slowest p95 first. Raw attempts only:
  # attempts without duration_ms (pre-feature) are excluded, not zero-filled.
  def latency_by_destination
    @latency_by_destination ||= begin
      rows = Attempt.joins(connection: :destination)
                    .where(connections: { project_id: project.id })
                    .where(attempted_at: window_start..)
                    .where.not(duration_ms: nil)
                    .group("destinations.id")
                    .pluck(Arel.sql("destinations.id"), Arel.sql("COUNT(*)"),
                           Arel.sql("PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY attempts.duration_ms)"),
                           Arel.sql("PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY attempts.duration_ms)"))
      destinations = project.destinations.where(id: rows.map(&:first)).index_by(&:id)
      rows.map do |id, count, p50, p95|
        { destination: destinations[id], count: count, p50: p50.round, p95: p95.round }
      end.sort_by { |r| -r[:p95] }
    end
  end

  private

  def window_start
    window == "24h" ? 23.hours.ago.beginning_of_hour : (Date.current - (DAYS[window] - 1)).beginning_of_day
  end

  def success_rate(delivered, failed)
    total = delivered + failed
    return nil if total.zero?

    delivered * 100.0 / total
  end

  def events_count(range)
    Event.joins(:source).where(sources: { project_id: project.id }, received_at: range).count
  end

  def hourly_buckets
    start = window_start
    events = Event.joins(:source)
                  .where(sources: { project_id: project.id }, received_at: start..)
                  .group(Arel.sql("date_trunc('hour', events.received_at)")).count
                  .transform_keys { |t| t.to_time.to_i }
    deliveries = hourly_delivery_counts(start..)
    (0..23).map do |i|
      hour = start + i.hours
      d = deliveries[hour.to_i] || {}
      { label: hour.strftime("%H:%M"), events: events[hour.to_i] || 0,
        delivered: d[:delivered] || 0, failed: d[:failed] || 0, pending: d[:pending] || 0 }
    end
  end

  # Same latest-attempt fold as .delivery_counts, bucketed by the hour the
  # event was received; keyed by epoch seconds to dodge Time-class equality.
  def hourly_delivery_counts(range)
    sub = Attempt.joins(:connection, :event)
                 .where(connections: { project_id: project.id })
                 .where(events: { received_at: range })
                 .select("DISTINCT ON (attempts.event_id, attempts.connection_id) attempts.status, " \
                         "date_trunc('hour', events.received_at) AS hour")
                 .order("attempts.event_id, attempts.connection_id, attempts.attempt_number DESC")
    Attempt.from(sub, :latest).group("latest.hour", "latest.status").count
           .each_with_object({}) do |((hour, status), n), acc|
      bucket = (acc[hour.to_time.to_i] ||= Hash.new(0))
      bucket[self.class.state_for(status)] += n
    end
  end

  def daily_buckets
    days = (Date.current - (DAYS[window] - 1))..Date.current
    past = rollups_by_day
    days.map do |day|
      row = day == Date.current ? live_day(day) : past[day]
      { label: day.strftime("%b %-d"), **row }
    end
  end

  def live_day(day)
    range = day.all_day
    totals = { delivered: 0, failed: 0, pending: 0 }
    self.class.delivery_counts(range, project: project).each_value do |counts|
      totals.each_key { |state| totals[state] += counts[state] }
    end
    { events: events_count(range), **totals }
  end

  def rollups_by_day
    acc = Hash.new { |h, k| h[k] = { events: 0, delivered: 0, failed: 0, pending: 0 } }
    rollups.each do |r|
      row = acc[r.day]
      if r.connection_id.nil?
        row[:events] += r.events_received
      else
        row[:delivered] += r.delivered_count
        row[:failed] += r.failed_count
        row[:pending] += r.pending_count
      end
    end
    acc
  end

  def rollups
    MetricRollup.where(project_id: project.id, day: (Date.current - (DAYS[window] - 1))...Date.current)
  end
end
