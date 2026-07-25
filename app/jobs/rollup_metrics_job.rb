class RollupMetricsJob < ApplicationJob
  queue_as :default

  # Recompute a trailing window each run: retry policies can flip a delivery's
  # state up to 7 days after its event, and the first run backfills history.
  # Beyond this window a day's numbers freeze. ponytail: full-window
  # delete+rewrite daily; shrink to changed-days-only if volume makes it slow.
  RECOMPUTE_DAYS = 30

  def perform
    # A project's raw rows reach back only as far as its org's retention, so
    # recomputing past that would delete rollups the raw data can no longer
    # rebuild. Each project's recompute window is min(RECOMPUTE_DAYS, retention).
    starts = Project.joins(:organization)
                    .pluck(:id, "organizations.retention_days")
                    .to_h { |id, r| [ id, [ Date.current - RECOMPUTE_DAYS, Date.current - r ].max ] }
    days = (Date.current - RECOMPUTE_DAYS)..Date.yesterday
    rows = days.flat_map { |day| MetricRollup.rows_for_day(day) }
               .select { |row| starts[row[:project_id]] && row[:day] >= starts[row[:project_id]] }
    MetricRollup.transaction do
      starts.each do |project_id, start|
        MetricRollup.where(project_id: project_id, day: start..Date.yesterday).delete_all
      end
      MetricRollup.insert_all(rows) if rows.any?
    end
  end
end
