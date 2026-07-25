require "test_helper"

class ReplayFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def issue_key!(org)
    ApiKey.issue!(organization: org, name: "test")
  end

  def auth(raw)
    { "Authorization" => "Bearer #{raw}" }
  end

  # source + destination + connection under `project`. Returns [source, connection].
  def build_connection!(project, url: "https://dest-#{SecureRandom.hex(3)}.test/hook")
    source      = Source.create!(project: project, name: "S-#{SecureRandom.hex(3)}")
    destination = Destination.create!(project: project, name: "D-#{SecureRandom.hex(3)}", url: url)
    connection  = Connection.create!(project: project, source: source, destination: destination)
    [ source, connection ]
  end

  # An event on `source`, with an attempt of `status` on `connection` if given.
  def make_event!(source, connection = nil, status: nil, received_at: Time.current)
    event = Event.create!(source: source, http_method: "POST", path: "/wh", received_at: received_at,
                          headers: { "Content-Type" => "application/json" }, body: %({"x":1}))
    Attempt.create!(event: event, connection: connection, attempt_number: 1,
                    attempted_at: Time.current, status: status) if status
    event
  end

  test "replay of a filtered set enqueues one job per matching event, flagged replay+pending" do
    project = create_test_project!
    org = project.organization
    _key, raw = issue_key!(org)
    source, connection = build_connection!(project)
    3.times { make_event!(source) }

    assert_enqueued_jobs(3, only: DeliverEventJob) do
      post "/api/v1/events/bulk_replay",
           params: { source_id: source.id, connection_id: connection.id }, headers: auth(raw), as: :json
    end
    assert_response :accepted
    assert_equal({ "enqueued" => 3 }, JSON.parse(response.body))

    attempts = Attempt.where(connection: connection)
    assert_equal 3, attempts.count
    assert attempts.all?(&:replay?)
    assert attempts.all?(&:pending?)
  end

  test "replay re-delivers an already-succeeded pair, bypassing the idempotency guard" do
    project = create_test_project!
    org = project.organization
    _key, raw = issue_key!(org)
    source, connection = build_connection!(project)
    event = make_event!(source, connection, status: :succeeded)

    assert_enqueued_jobs(1, only: DeliverEventJob) do
      post "/api/v1/events/bulk_replay",
           params: { source_id: source.id, connection_id: connection.id }, headers: auth(raw), as: :json
    end
    assert_equal({ "enqueued" => 1 }, JSON.parse(response.body))

    stub_request(:post, connection.destination.url).to_return(status: 200, body: "ok")
    perform_enqueued_jobs

    succeeded = Attempt.where(event: event, connection: connection, status: :succeeded).order(:attempt_number)
    assert_equal 2, succeeded.count
    assert succeeded.last.replay?
  end

  test "non-replay delivery stays idempotent: a succeeded pair gets no new attempt" do
    project = create_test_project!
    source, connection = build_connection!(project)
    event = make_event!(source, connection, status: :succeeded)

    DeliverEventJob.perform_now(event.id, connection.id)

    assert_equal 1, Attempt.where(event: event, connection: connection).count
  end

  test "an in-flight pair is skipped by replay" do
    project = create_test_project!
    org = project.organization
    _key, raw = issue_key!(org)
    source, connection = build_connection!(project)
    make_event!(source, connection, status: :pending)

    assert_no_enqueued_jobs do
      post "/api/v1/events/bulk_replay",
           params: { source_id: source.id, connection_id: connection.id }, headers: auth(raw), as: :json
    end
    assert_response :accepted
    assert_equal({ "enqueued" => 0 }, JSON.parse(response.body))
  end

  test "replay respects the connection's routing rule" do
    project = create_test_project!
    org = project.organization
    _key, raw = issue_key!(org)
    source = Source.create!(project: project, name: "S1")
    destination = Destination.create!(project: project, name: "D1", url: "https://d.test/hook")
    connection = Connection.create!(project: project, source: source, destination: destination,
                                     routing_rule: { "body" => { "type" => "invoice.paid" } })
    matching = Event.create!(source: source, http_method: "POST", path: "/wh", received_at: Time.current,
                              headers: {}, body: '{"type":"invoice.paid"}')
    Event.create!(source: source, http_method: "POST", path: "/wh", received_at: Time.current,
                  headers: {}, body: '{"type":"invoice.created"}')

    assert_enqueued_jobs(1, only: DeliverEventJob) do
      post "/api/v1/events/bulk_replay",
           params: { source_id: source.id, connection_id: connection.id }, headers: auth(raw), as: :json
    end
    assert_equal({ "enqueued" => 1 }, JSON.parse(response.body))
    assert_enqueued_with(job: DeliverEventJob, args: [ matching.id, connection.id, { replay: true } ])
  end

  test "outbound request carries X-Hookrail-Replay only on a replay, not on a normal delivery" do
    project = create_test_project!
    org = project.organization
    _key, raw = issue_key!(org)
    source, connection = build_connection!(project)
    event = make_event!(source)

    replay_captured = nil
    stub_request(:post, connection.destination.url)
      .with { |req| replay_captured = req; true }
      .to_return(status: 200)

    perform_enqueued_jobs do
      post "/api/v1/events/bulk_replay",
           params: { source_id: source.id, connection_id: connection.id }, headers: auth(raw), as: :json
    end
    assert_equal "true", replay_captured.headers["X-Hookrail-Replay"]

    normal_captured = nil
    stub_request(:post, connection.destination.url)
      .with { |req| normal_captured = req; true }
      .to_return(status: 200)
    other_event = make_event!(source)
    perform_enqueued_jobs { DeliverEventJob.perform_later(other_event.id, connection.id) }
    assert_nil normal_captured.headers["X-Hookrail-Replay"]
  end

  test "cross-org connection_id 404s" do
    project_a = create_test_project!
    source_a, connection_a = build_connection!(project_a)

    project_b = create_test_project!
    _key_b, raw_b = issue_key!(project_b.organization)

    post "/api/v1/events/bulk_replay",
         params: { source_id: source_a.id, connection_id: connection_a.id }, headers: auth(raw_b), as: :json
    assert_response :not_found
    assert_equal "not_found", JSON.parse(response.body)["error"]["code"]
  end

  test "date-range filter limits the replayed set" do
    project = create_test_project!
    org = project.organization
    _key, raw = issue_key!(org)
    source, connection = build_connection!(project)
    make_event!(source, received_at: 10.days.ago)
    in_range = make_event!(source, received_at: 1.day.ago)

    assert_enqueued_jobs(1, only: DeliverEventJob) do
      post "/api/v1/events/bulk_replay",
           params: { source_id: source.id, connection_id: connection.id,
                     from: 3.days.ago.to_date.to_s, to: Date.current.to_s },
           headers: auth(raw), as: :json
    end
    assert_equal({ "enqueued" => 1 }, JSON.parse(response.body))
    assert_enqueued_with(job: DeliverEventJob, args: [ in_range.id, connection.id, { replay: true } ])
  end
end
