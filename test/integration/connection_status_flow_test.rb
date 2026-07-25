require "test_helper"

class ConnectionStatusFlowTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper
  include ActiveJob::TestHelper

  def issue_key!(org)
    ApiKey.issue!(organization: org, name: "test")
  end

  def auth(raw)
    { "Authorization" => "Bearer #{raw}" }
  end

  def build_connection!(project, url: "https://dest-#{SecureRandom.hex(3)}.test/hook")
    source      = Source.create!(project: project, name: "S-#{SecureRandom.hex(3)}")
    destination = Destination.create!(project: project, name: "D-#{SecureRandom.hex(3)}", url: url)
    connection  = Connection.create!(project: project, source: source, destination: destination)
    [ source, destination, connection ]
  end

  def ingest!(source, body:)
    post ingest_path(token: source.token), params: body, headers: { "Content-Type" => "application/json" }
  end

  def make_event!(source)
    source.events.create!(http_method: "POST", path: "/wh", received_at: Time.current,
                          headers: { "Content-Type" => "application/json" }, body: '{"a":1}')
  end

  test "a new connection is active and the API rejects an unknown status" do
    project = create_test_project!
    org = project.organization
    _key, raw = issue_key!(org)
    _source, _destination, connection = build_connection!(project)

    assert_equal "active", connection.status

    put "/api/v1/connections/#{connection.id}", params: { connection: { status: "bogus" } },
        headers: auth(raw), as: :json
    assert_response :unprocessable_entity
    assert_equal "validation_failed", JSON.parse(response.body)["error"]["code"]

    put "/api/v1/connections/#{connection.id}", params: { connection: { status: "paused" } },
        headers: auth(raw), as: :json
    assert_response :ok
    assert_equal "paused", JSON.parse(response.body)["connection"]["status"]
  end

  test "paused connection holds matched events and drains them in order on resume" do
    project = create_test_project!
    org = project.organization
    _key, raw = issue_key!(org)
    source, destination, connection = build_connection!(project)
    connection.update!(status: "paused")

    ingest!(source, body: '{"a":1}')
    assert_response :success
    ingest!(source, body: '{"a":2}')
    assert_response :success

    events = source.events.order(:received_at, :id).to_a
    assert_equal 2, events.size

    perform_enqueued_jobs only: DeliverEventJob

    assert_not_requested :post, destination.url
    assert_equal [ "held", "held" ], Attempt.where(connection: connection).order(:event_id).pluck(:status)

    connection.update!(status: "active")

    jobs = enqueued_jobs.select { |j| j[:job] == DeliverEventJob }
    assert_equal events.map(&:id), jobs.map { |j| j[:args][0] }

    stub = stub_request(:post, destination.url).to_return(status: 200, body: "ok")
    perform_enqueued_jobs only: DeliverEventJob

    assert_requested stub, times: 2
    assert_equal [ "succeeded", "succeeded" ], Attempt.where(connection: connection).order(:event_id).pluck(:status)
  end

  test "disabled connection ingests events but creates no deliveries and never back-delivers" do
    project = create_test_project!
    org = project.organization
    _key, raw = issue_key!(org)
    source, _destination, connection = build_connection!(project)
    connection.update!(status: "disabled")

    ingest!(source, body: '{"a":1}')
    assert_response :success

    assert_equal 1, source.events.count
    assert_equal 0, Attempt.where(connection: connection).count
    assert_no_enqueued_jobs only: DeliverEventJob

    connection.update!(status: "active")
    assert_no_enqueued_jobs only: DeliverEventJob
  end

  test "pausing mid-retry holds the chain and resume completes it" do
    project = create_test_project!
    org = project.organization
    _key, raw = issue_key!(org)
    source, destination, connection = build_connection!(project)
    event = make_event!(source)

    stub = stub_request(:post, destination.url).to_return(status: 500, body: "err")
    DeliverEventJob.perform_now(event.id, connection.id)

    assert_requested stub, times: 1
    assert_equal 1, connection.reload.consecutive_failures
    assert Attempt.where(connection: connection).order(:attempt_number).last.failed?

    connection.update!(status: "paused")

    DeliverEventJob.perform_now(event.id, connection.id)

    assert_requested stub, times: 1
    latest = Attempt.where(connection: connection).order(:attempt_number).last
    assert_equal "held", latest.status

    stub_request(:post, destination.url).to_return(status: 200, body: "ok")
    connection.update!(status: "active")
    perform_enqueued_jobs only: DeliverEventJob

    latest = Attempt.where(connection: connection).order(:attempt_number).last
    assert latest.succeeded?
  end

  test "disabling cancels held and pending deliveries" do
    project = create_test_project!
    org = project.organization
    _key, raw = issue_key!(org)
    source, _destination, connection = build_connection!(project)
    connection.update!(status: "paused")

    ingest!(source, body: '{"a":1}')
    assert_response :success
    perform_enqueued_jobs only: DeliverEventJob

    assert_equal 1, Attempt.where(connection: connection, status: "held").count

    connection.update!(status: "disabled")
    assert_equal 0, Attempt.where(connection: connection).count
  end

  test "a non-active connection records no failures and sends no alerts" do
    project = create_test_project!
    org = project.organization
    org.update!(alert_webhook_url: "https://alerts.test/hook")
    _key, raw = issue_key!(org)
    source, _destination, connection = build_connection!(project)
    connection.update!(status: "paused")

    assert_no_enqueued_emails do
      ingest!(source, body: '{"a":1}')
      perform_enqueued_jobs only: DeliverEventJob
    end
    assert_response :success

    assert_equal 0, connection.reload.consecutive_failures
    assert_no_enqueued_jobs only: AlertWebhookJob
  end

  test "replay and retry are refused on non-active connections" do
    project = create_test_project!
    org = project.organization
    _key, raw = issue_key!(org)
    source, _destination, connection = build_connection!(project)
    event = make_event!(source)
    Attempt.create!(event: event, connection: connection, attempt_number: 1,
                    attempted_at: Time.current, status: "failed")

    connection.update!(status: "paused")

    assert_empty Attempt.retryable_for(Event.where(id: event.id))

    post "/api/v1/events/bulk_replay", params: { connection_id: connection.id }, headers: auth(raw), as: :json
    assert_response :unprocessable_entity
    assert_equal "connection_not_active", JSON.parse(response.body)["error"]["code"]

    post "/api/v1/events/#{event.id}/retries", params: { connection_id: connection.id },
                                                headers: auth(raw), as: :json
    assert_response :unprocessable_entity
    assert_equal "connection_not_active", JSON.parse(response.body)["error"]["code"]

    connection.update!(status: "active")
    assert_not_empty Attempt.retryable_for(Event.where(id: event.id))
  end
end
