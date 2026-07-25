class RollupMetricsJob < ApplicationJob
  queue_as :default

  # Recompute a trailing window each run: retry policies can flip a delivery's
  # state up to 7 days after its event, and the first run backfills history.
  # Beyond this window a day's numbers freeze. ponytail: full-window
  # delete+rewrite daily; shrink to changed-days-only if volume makes it slow.
  RECOMPUTE_DAYS = 30

  def perform
    days = (Date.current - RECOMPUTE_DAYS)..Date.yesterday
    rows = days.flat_map { |day| MetricRollup.rows_for_day(day) }
    MetricRollup.transaction do
      MetricRollup.where(day: days).delete_all
      MetricRollup.insert_all(rows) if rows.any?
    end
  end
end
