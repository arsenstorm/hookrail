require "test_helper"

class MetricsFlowTest < ActiveSupport::TestCase
  def build_connection!(project)
    source      = Source.create!(project: project, name: "S-#{SecureRandom.hex(3)}")
    destination = Destination.create!(project: project, name: "D-#{SecureRandom.hex(3)}",
                                      url: "https://dest-#{SecureRandom.hex(3)}.test/hook")
    connection  = Connection.create!(project: project, source: source, destination: destination)
    [ source, destination, connection ]
  end

  def event!(source, at:)
    source.events.create!(http_method: "POST", path: "/wh", received_at: at, headers: {}, body: "{}")
  end

  def attempt!(event, connection, status:, number: 1, at: Time.current, duration_ms: nil)
    Attempt.create!(event: event, connection: connection, attempt_number: number,
                    status: status, attempted_at: at, duration_ms: duration_ms)
  end

  test "totals cover the selected window and fall back to 24h" do
    travel_to Time.zone.parse("2026-07-15 12:00") do
      project = create_test_project!
      _source, _destination, connection = build_connection!(project)

      event_a = event!(_source, at: Time.current)
      attempt!(event_a, connection, status: "succeeded")

      event_b = event!(_source, at: Time.current)
      attempt!(event_b, connection, status: "failed", number: 1)
      attempt!(event_b, connection, status: "dead", number: 2)

      event_c = event!(_source, at: 3.days.ago)
      attempt!(event_c, connection, status: "succeeded", at: 3.days.ago)

      event!(_source, at: 10.days.ago)

      RollupMetricsJob.perform_now

      totals_24h = Metrics.new(project: project, window: "24h").totals
      assert_equal 2, totals_24h[:events_received]
      assert_equal 1, totals_24h[:delivered]
      assert_equal 1, totals_24h[:failed]
      assert_equal 0, totals_24h[:pending]
      assert_equal 50.0, totals_24h[:success_rate]

      totals_7d = Metrics.new(project: project, window: "7d").totals
      assert_equal 3, totals_7d[:events_received]
      assert_equal 2, totals_7d[:delivered]
      assert_equal 1, totals_7d[:failed]

      totals_30d = Metrics.new(project: project, window: "30d").totals
      assert_equal 4, totals_30d[:events_received]

      assert_equal "24h", Metrics.new(project: project, window: "bogus").window
    end
  end

  test "by_connection reports per-connection health" do
    travel_to Time.zone.parse("2026-07-15 12:00") do
      project = create_test_project!
      source1, _dest1, connection1 = build_connection!(project)
      source2, _dest2, connection2 = build_connection!(project)

      e1 = event!(source1, at: Time.current)
      attempt!(e1, connection1, status: "succeeded")
      e2 = event!(source1, at: Time.current)
      attempt!(e2, connection1, status: "succeeded")

      e3 = event!(source2, at: Time.current)
      attempt!(e3, connection2, status: "dead")

      e4 = event!(source2, at: Time.current)
      attempt!(e4, connection2, status: "failed", number: 1)
      attempt!(e4, connection2, status: "pending", number: 2)

      rows = Metrics.new(project: project, window: "24h").by_connection

      row1 = rows.find { |r| r[:connection] == connection1 }
      assert_equal 2, row1[:events]
      assert_equal 2, row1[:delivered]
      assert_equal 100.0, row1[:success_rate]

      row2 = rows.find { |r| r[:connection] == connection2 }
      assert_equal 2, row2[:events]
      assert_equal 1, row2[:failed]
      assert_equal 1, row2[:pending]
      assert_equal 0.0, row2[:success_rate]
    end
  end

  test "latency percentiles per destination exclude missing durations" do
    travel_to Time.zone.parse("2026-07-15 12:00") do
      project = create_test_project!
      source, _destination, connection = build_connection!(project)

      [ 100, 200, 300, 400 ].each do |ms|
        e = event!(source, at: Time.current)
        attempt!(e, connection, status: "succeeded", at: Time.current, duration_ms: ms)
      end

      e_nil = event!(source, at: Time.current)
      attempt!(e_nil, connection, status: "succeeded", at: Time.current, duration_ms: nil)

      e_old = event!(source, at: 2.days.ago)
      attempt!(e_old, connection, status: "succeeded", at: 2.days.ago, duration_ms: 5000)

      rows_24h = Metrics.new(project: project, window: "24h").latency_by_destination
      assert_equal 1, rows_24h.size
      assert_equal 4, rows_24h.first[:count]
      assert_equal 250, rows_24h.first[:p50]
      assert_equal 385, rows_24h.first[:p95]

      rows_30d = Metrics.new(project: project, window: "30d").latency_by_destination
      assert_equal 5, rows_30d.first[:count]
    end
  end

  test "rollups keep window totals correct after raw rows are pruned" do
    travel_to Time.zone.parse("2026-07-15 12:00") do
      project = create_test_project!
      source, _destination, connection = build_connection!(project)

      old_event = event!(source, at: 3.days.ago)
      attempt!(old_event, connection, status: "succeeded", at: 3.days.ago)

      event!(source, at: Time.current).tap do |e|
        attempt!(e, connection, status: "succeeded")
      end

      RollupMetricsJob.perform_now

      Attempt.where(event_id: old_event.id).delete_all
      old_event.destroy

      totals = Metrics.new(project: project, window: "7d").totals
      assert_equal 2, totals[:events_received]
      assert_equal 2, totals[:delivered]
      assert_equal 100.0, totals[:success_rate]
    end
  end

  test "buckets match the window shape" do
    travel_to Time.zone.parse("2026-07-15 12:00") do
      project = create_test_project!

      buckets_24h = Metrics.new(project: project, window: "24h").buckets
      assert_equal 24, buckets_24h.size
      assert(buckets_24h.all? { |b| b[:label].match?(/\A\d{2}:\d{2}\z/) })

      buckets_7d = Metrics.new(project: project, window: "7d").buckets
      assert_equal 7, buckets_7d.size

      buckets_30d = Metrics.new(project: project, window: "30d").buckets
      assert_equal 30, buckets_30d.size
      assert_equal Date.current.strftime("%b %-d"), buckets_30d.last[:label]
      assert(buckets_30d.all? { |b| b[:events].zero? && b[:delivered].zero? && b[:failed].zero? && b[:pending].zero? })
    end
  end

  test "metrics are project-scoped" do
    travel_to Time.zone.parse("2026-07-15 12:00") do
      project_a = create_test_project!
      project_b = create_test_project!
      source_a, destination_a, connection_a = build_connection!(project_a)
      source_b, _destination_b, connection_b = build_connection!(project_b)

      event_a = event!(source_a, at: Time.current)
      attempt!(event_a, connection_a, status: "succeeded", at: Time.current, duration_ms: 100)

      event_b = event!(source_b, at: Time.current)
      attempt!(event_b, connection_b, status: "succeeded", at: Time.current, duration_ms: 900)

      metrics_a = Metrics.new(project: project_a, window: "24h")
      assert_equal 1, metrics_a.totals[:events_received]
      assert_equal [ connection_a ], metrics_a.by_connection.map { |r| r[:connection] }
      assert_equal [ destination_a ], metrics_a.latency_by_destination.map { |r| r[:destination] }
      assert_equal 100, metrics_a.latency_by_destination.first[:p50]
    end
  end

  test "rollup job is idempotent" do
    travel_to Time.zone.parse("2026-07-15 12:00") do
      project = create_test_project!
      source, _destination, connection = build_connection!(project)

      past_event = event!(source, at: 3.days.ago)
      attempt!(past_event, connection, status: "succeeded", at: 3.days.ago)

      RollupMetricsJob.perform_now
      count_after_first = MetricRollup.count
      totals_after_first = Metrics.new(project: project, window: "7d").totals

      RollupMetricsJob.perform_now
      count_after_second = MetricRollup.count
      totals_after_second = Metrics.new(project: project, window: "7d").totals

      assert_equal count_after_first, count_after_second
      assert_equal totals_after_first, totals_after_second
    end
  end
end
