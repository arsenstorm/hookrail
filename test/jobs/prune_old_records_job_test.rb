require "test_helper"

class PruneOldRecordsJobTest < ActiveJob::TestCase
  test "deletes records older than 30 days and keeps recent ones" do
    project = create_test_project!
    source = Source.create!(project: project, name: "GitHub")
    connection = build_connection!(project, source)

    old_event = create_event!(source, received_at: 31.days.ago)
    create_attempt!(old_event, connection, attempted_at: 31.days.ago)
    recent_event = create_event!(source, received_at: 29.days.ago)
    recent_attempt = create_attempt!(recent_event, connection, attempted_at: 29.days.ago)

    old_quarantined = create_quarantined_webhook!(source, received_at: 31.days.ago)
    recent_quarantined = create_quarantined_webhook!(source, received_at: 29.days.ago)

    PruneOldRecordsJob.perform_now

    assert_not Event.exists?(old_event.id)
    assert Event.exists?(recent_event.id)
    assert_not QuarantinedWebhook.exists?(old_quarantined.id)
    assert QuarantinedWebhook.exists?(recent_quarantined.id)
    assert Attempt.exists?(recent_attempt.id)
  end

  test "leaves no attempts whose event is gone" do
    project = create_test_project!
    source = Source.create!(project: project, name: "GitHub")
    connection = build_connection!(project, source)

    old_event = create_event!(source, received_at: 31.days.ago)
    create_attempt!(old_event, connection, attempted_at: 31.days.ago, attempt_number: 1)
    create_attempt!(old_event, connection, attempted_at: 31.days.ago, attempt_number: 2)

    PruneOldRecordsJob.perform_now

    assert Attempt.where.missing(:event).none?
    assert Attempt.where(event_id: old_event.id).none?
  end

  test "deletes all eligible rows across multiple batches" do
    project = create_test_project!
    source = Source.create!(project: project, name: "GitHub")

    3.times { create_event!(source, received_at: 31.days.ago) }
    3.times { create_quarantined_webhook!(source, received_at: 31.days.ago) }

    PruneOldRecordsJob.perform_now(batch_size: 1)

    assert Event.where(received_at: ...30.days.ago).none?
    assert QuarantinedWebhook.where(received_at: ...30.days.ago).none?
  end

  private

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

  def create_attempt!(event, connection, attempted_at:, attempt_number: 1)
    Attempt.create!(
      event: event, connection: connection, attempt_number: attempt_number,
      status: :succeeded, attempted_at: attempted_at
    )
  end

  def create_quarantined_webhook!(source, received_at:)
    source.quarantined_webhooks.create!(
      http_method: "POST", headers: {}, reason: "signature mismatch", received_at: received_at
    )
  end
end
