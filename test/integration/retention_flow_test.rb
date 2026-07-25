require "test_helper"

class RetentionFlowTest < ActionDispatch::IntegrationTest
  def issue_key!(org)
    ApiKey.issue!(organization: org, name: "test")
  end

  def auth(raw)
    { "Authorization" => "Bearer #{raw}" }
  end

  def build_connection!(project, source)
    destination = Destination.create!(project: project, name: "API", url: "https://dest.test/hook")
    Connection.create!(project: project, source: source, destination: destination)
  end

  def create_event!(source, received_at:)
    source.events.create!(
      http_method: "POST", path: "/wh", received_at: received_at,
      headers: { "Content-Type" => "application/json" }, body: %({"x":1})
    )
  end

  def create_attempt!(event, connection, attempted_at:, status: :succeeded, attempt_number: 1)
    Attempt.create!(
      event: event, connection: connection, attempt_number: attempt_number,
      status: status, attempted_at: attempted_at
    )
  end

  def create_quarantined_webhook!(source, received_at:)
    source.quarantined_webhooks.create!(
      http_method: "POST", headers: {}, reason: "signature mismatch", received_at: received_at
    )
  end

  test "retention_days validates 7, 30, or 90 with default 30" do
    org = create_test_project!.organization
    assert_equal 30, org.retention_days

    [ 7, 30, 90 ].each do |v|
      org.retention_days = v
      assert org.valid?
    end

    org.retention_days = 14
    assert_not org.valid?
    assert_includes org.errors.full_messages.to_sentence, "must be 7, 30, or 90 days"

    org.retention_days = nil
    assert_not org.valid?
  end

  test "prune deletes per-org out-of-window rows and keeps young ones" do
    project_a = create_test_project!
    project_b = create_test_project!
    org_a = project_a.organization
    org_b = project_b.organization
    org_a.update!(retention_days: 7)
    org_b.update!(retention_days: 90)

    source_a = Source.create!(project: project_a, name: "S-A")
    connection_a = build_connection!(project_a, source_a)
    old_event_a = create_event!(source_a, received_at: 10.days.ago)
    create_attempt!(old_event_a, connection_a, attempted_at: 10.days.ago)
    fresh_event_a = create_event!(source_a, received_at: 1.day.ago)
    create_attempt!(fresh_event_a, connection_a, attempted_at: 1.day.ago)
    old_quarantined_a = create_quarantined_webhook!(source_a, received_at: 10.days.ago)

    source_b = Source.create!(project: project_b, name: "S-B")
    connection_b = build_connection!(project_b, source_b)
    old_event_b = create_event!(source_b, received_at: 10.days.ago)
    old_attempt_b = create_attempt!(old_event_b, connection_b, attempted_at: 10.days.ago)
    fresh_event_b = create_event!(source_b, received_at: 1.day.ago)
    create_attempt!(fresh_event_b, connection_b, attempted_at: 1.day.ago)
    old_quarantined_b = create_quarantined_webhook!(source_b, received_at: 10.days.ago)

    PruneOldRecordsJob.perform_now(batch_size: 1)

    assert_not Event.exists?(old_event_a.id)
    assert_not Attempt.where(event_id: old_event_a.id).exists?
    assert_not QuarantinedWebhook.exists?(old_quarantined_a.id)
    assert Event.exists?(fresh_event_a.id)

    assert Event.exists?(old_event_b.id)
    assert Attempt.exists?(old_attempt_b.id)
    assert QuarantinedWebhook.exists?(old_quarantined_b.id)
    assert Event.exists?(fresh_event_b.id)
  end

  test "rollups survive pruning and out-of-retention rollups survive recompute" do
    travel_to Time.zone.parse("2026-07-15 12:00") do
      project = create_test_project!
      project.organization.update!(retention_days: 7)

      source = Source.create!(project: project, name: "S")
      connection = build_connection!(project, source)
      event = create_event!(source, received_at: 3.days.ago)
      create_attempt!(event, connection, attempted_at: 3.days.ago)

      RollupMetricsJob.perform_now

      MetricRollup.create!(project_id: project.id, connection_id: nil, day: 20.days.ago.to_date,
                            events_received: 5, delivered_count: 0, failed_count: 0, pending_count: 0)

      PruneOldRecordsJob.perform_now

      assert MetricRollup.exists?(project_id: project.id, connection_id: nil, day: 20.days.ago.to_date)
      assert MetricRollup.exists?(project_id: project.id, connection_id: nil, day: 3.days.ago.to_date)

      RollupMetricsJob.perform_now

      assert MetricRollup.exists?(project_id: project.id, connection_id: nil, day: 20.days.ago.to_date)
      day3_rollup = MetricRollup.find_by(project_id: project.id, connection_id: nil, day: 3.days.ago.to_date)
      assert_equal 1, day3_rollup.events_received
    end
  end

  test "pruning never touches configuration" do
    project = create_test_project!
    source = Source.create!(project: project, name: "S")
    destination = Destination.create!(project: project, name: "D", url: "https://dest.test/hook")
    connection = Connection.create!(project: project, source: source, destination: destination)
    api_key, _raw = ApiKey.issue!(organization: project.organization, name: "test")
    event = create_event!(source, received_at: Time.current)

    travel 100.days do
      PruneOldRecordsJob.perform_now
    end

    assert_not Event.exists?(event.id)
    assert Source.exists?(source.id)
    assert Destination.exists?(destination.id)
    assert Connection.exists?(connection.id)
    assert ApiKey.exists?(api_key.id)
    assert Organization.exists?(project.organization.id)
  end

  test "events with an in-flight attempt are skipped until terminal" do
    project = create_test_project!
    source = Source.create!(project: project, name: "S")
    connection = build_connection!(project, source)
    event = create_event!(source, received_at: 40.days.ago)
    attempt = create_attempt!(event, connection, attempted_at: 40.days.ago, status: :pending)

    PruneOldRecordsJob.perform_now
    assert Event.exists?(event.id)

    attempt.update!(status: :succeeded)
    PruneOldRecordsJob.perform_now
    assert_not Event.exists?(event.id)
    assert_not Attempt.exists?(attempt.id)
  end

  test "retention is readable and writable via the API" do
    project = create_test_project!
    _key, raw = issue_key!(project.organization)

    get "/api/v1/retention", headers: auth(raw)
    assert_response :ok
    assert_equal({ "retention" => { "days" => 30 } }, JSON.parse(response.body))

    patch "/api/v1/retention", params: { retention: { days: 90 } }, headers: auth(raw), as: :json
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal 90, body["retention"]["days"]
    assert_equal 90, project.organization.reload.retention_days

    patch "/api/v1/retention", params: { retention: { days: 14 } }, headers: auth(raw), as: :json
    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "validation_failed", body["error"]["code"]
    assert_equal 90, project.organization.reload.retention_days
  end
end
