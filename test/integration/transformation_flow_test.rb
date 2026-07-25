require "test_helper"

class TransformationFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def issue_key!(org)
    ApiKey.issue!(organization: org, name: "test")
  end

  def auth(raw)
    { "Authorization" => "Bearer #{raw}" }
  end

  # source + destination + connection under `project`. Returns [source, connection].
  def build_connection!(project, url: "https://dest-#{SecureRandom.hex(3)}.test/hook", transformation: nil)
    source      = Source.create!(project: project, name: "S-#{SecureRandom.hex(3)}")
    destination = Destination.create!(project: project, name: "D-#{SecureRandom.hex(3)}", url: url)
    connection  = Connection.create!(project: project, source: source, destination: destination,
                                      transformation: transformation)
    [ source, connection ]
  end

  def make_event!(source, body: %({"type":"x"}))
    Event.create!(source: source, http_method: "POST", path: "/wh", received_at: Time.current,
                  headers: { "Content-Type" => "application/json" }, body: body)
  end

  ADD_HEADER_TRANSFORM = <<~JS
    function transform(r) {
      var headers = r.headers;
      headers["X-Env"] = "test";
      return { headers: headers, body: { got: r.body.type } };
    }
  JS

  THROWING_TRANSFORM = 'function transform(r) { throw new Error("boom"); }'

  test "connection without a transformation delivers the body byte-identically" do
    project = create_test_project!
    source, connection = build_connection!(project)
    event = make_event!(source)
    stub = stub_request(:post, connection.destination.url).with(body: event.body).to_return(status: 200, body: "ok")

    perform_enqueued_jobs { DeliverEventJob.perform_later(event.id, connection.id) }

    assert_requested stub
    attempt = Attempt.where(event: event, connection: connection).sole
    assert attempt.succeeded?
    assert_nil attempt.transformed_body
  end

  test "connection with a transformation reshapes headers and body, and records them" do
    project = create_test_project!
    source, connection = build_connection!(project, transformation: ADD_HEADER_TRANSFORM)
    event = make_event!(source)
    captured = nil
    stub_request(:post, connection.destination.url)
      .with { |req| captured = req; true }
      .to_return(status: 200, body: "ok")

    perform_enqueued_jobs { DeliverEventJob.perform_later(event.id, connection.id) }

    assert_equal '{"got":"x"}', captured.body
    assert_equal "test", captured.headers["X-Env"]

    attempt = Attempt.where(event: event, connection: connection).sole
    assert attempt.succeeded?
    assert_equal "test", attempt.transformed_headers["X-Env"]
    assert_equal '{"got":"x"}', attempt.transformed_body
  end

  test "a throwing transform fails the delivery without any outbound request" do
    project = create_test_project!
    source, connection = build_connection!(project, transformation: THROWING_TRANSFORM)
    event = make_event!(source)
    stub = stub_request(:post, connection.destination.url).to_return(status: 200)

    # perform_now (not perform_later + perform_enqueued_jobs) so retry_on's
    # rescheduled retry stays queued rather than draining the whole backoff
    # chain within this call.
    DeliverEventJob.perform_now(event.id, connection.id)

    assert_not_requested stub
    attempt = Attempt.where(event: event, connection: connection).sole
    assert attempt.failed?
    assert attempt.error.start_with?("TransformationError:")
    assert_nil attempt.response_status
    assert_equal 1, connection.reload.consecutive_failures
  end

  test "transform applies on manual retry" do
    project = create_test_project!
    source, connection = build_connection!(project, transformation: ADD_HEADER_TRANSFORM)
    event = make_event!(source)
    stub_request(:post, connection.destination.url).to_return(status: 500)
    DeliverEventJob.perform_now(event.id, connection.id)
    assert Attempt.where(event: event, connection: connection).sole.failed?

    captured = nil
    stub_request(:post, connection.destination.url)
      .with { |req| captured = req; true }
      .to_return(status: 200)

    perform_enqueued_jobs { Attempt.claim_retry!(event_id: event.id, connection_id: connection.id) }

    assert_equal '{"got":"x"}', captured.body
  end

  test "transform applies on replay, alongside the replay header" do
    project = create_test_project!
    source, connection = build_connection!(project, transformation: ADD_HEADER_TRANSFORM)
    event = make_event!(source)
    Attempt.create!(event: event, connection: connection, attempt_number: 1,
                    attempted_at: Time.current, status: :succeeded)

    captured = nil
    stub_request(:post, connection.destination.url)
      .with { |req| captured = req; true }
      .to_return(status: 200)

    perform_enqueued_jobs { Attempt.claim_retry!(event_id: event.id, connection_id: connection.id, replay: true) }

    assert_equal '{"got":"x"}', captured.body
    assert_equal "true", captured.headers["X-Hookrail-Replay"]
  end

  test "saving a connection with syntax-broken transformation code is invalid" do
    project = create_test_project!
    source = Source.create!(project: project, name: "S1")
    destination = Destination.create!(project: project, name: "D1", url: "https://d.test/hook")

    broken = Connection.new(project: project, source: source, destination: destination,
                            transformation: "function transform(r) {")
    assert_not broken.valid?
    assert broken.errors[:transformation].any?

    valid = Connection.new(project: project, source: source, destination: destination,
                           transformation: "function transform(r) { return r; }")
    assert valid.valid?
  end

  test "preview API runs a transform against a stored event without delivering" do
    project = create_test_project!
    org = project.organization
    _key, raw = issue_key!(org)
    source, connection = build_connection!(project)
    event = make_event!(source)
    stub = stub_request(:post, connection.destination.url).to_return(status: 200)

    post "/api/v1/connections/#{connection.id}/transformation_preview",
         params: { event_id: event.id, code: ADD_HEADER_TRANSFORM }, headers: auth(raw), as: :json
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal "test", body["preview"]["headers"]["X-Env"]
    assert_equal({ "got" => "x" }, JSON.parse(body["preview"]["body"]))
    assert_not_requested stub

    post "/api/v1/connections/#{connection.id}/transformation_preview",
         params: { event_id: event.id, code: THROWING_TRANSFORM }, headers: auth(raw), as: :json
    assert_response :unprocessable_entity
    assert_equal "transformation_failed", JSON.parse(response.body)["error"]["code"]

    other_project = create_test_project!
    other_source = Source.create!(project: other_project, name: "Other")
    other_event = make_event!(other_source)
    post "/api/v1/connections/#{connection.id}/transformation_preview",
         params: { event_id: other_event.id, code: ADD_HEADER_TRANSFORM }, headers: auth(raw), as: :json
    assert_response :not_found

    post "/api/v1/connections/#{connection.id}/transformation_preview",
         params: { event_id: event.id }, headers: auth(raw), as: :json
    assert_response :unprocessable_entity
    assert_equal "transformation_failed", JSON.parse(response.body)["error"]["code"]
  end
end
