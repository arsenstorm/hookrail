# One day of aggregated metrics: a project-level row (connection_id nil) holds
# events_received; one row per connection holds delivery-state counts. Derived
# data — no FKs, so pruning or deleting parents never blocks; rows for deleted
# connections are skipped at read time but keep project totals honest.
class MetricRollup < ApplicationRecord
  def self.rows_for_day(day)
    now = Time.current
    range = day.all_day
    project_ids = Connection.pluck(:id, :project_id).to_h

    event_rows = Event.joins(:source).where(received_at: range)
                      .group("sources.project_id").count
                      .map do |project_id, n|
      { project_id: project_id, connection_id: nil, day: day, events_received: n,
        delivered_count: 0, failed_count: 0, pending_count: 0,
        created_at: now, updated_at: now }
    end

    delivery_rows = Metrics.delivery_counts(range).filter_map do |connection_id, counts|
      project_id = project_ids[connection_id]
      next unless project_id

      { project_id: project_id, connection_id: connection_id, day: day, events_received: 0,
        delivered_count: counts[:delivered], failed_count: counts[:failed],
        pending_count: counts[:pending], created_at: now, updated_at: now }
    end

    event_rows + delivery_rows
  end
end
