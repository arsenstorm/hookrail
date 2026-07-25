require "test_helper"

class RateLimitFlowTest < ActionDispatch::IntegrationTest
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

  def make_event!(source)
    source.events.create!(http_method: "POST", path: "/wh", received_at: Time.current,
                          headers: { "Content-Type" => "application/json" }, body: '{"a":1}')
  end

  def ingest!(source, body:)
    post ingest_path(token: source.token), params: body, headers: { "Content-Type" => "application/json" }
  end

  test "API validates rate limit bounds and round-trips a valid one" do
    project = create_test_project!
    org = project.organization
    _key, raw = issue_key!(org)
    _source, destination, _connection = build_connection!(project)

    [
      { rate_limit: 0 },
      { rate_limit: 101, rate_limit_period: "second" },
      { rate_limit: 6001, rate_limit_period: "minute" },
      { rate_limit: 10, rate_limit_period: "hour" }
    ].each do |invalid_body|
      patch "/api/v1/destinations/#{destination.id}", params: { destination: invalid_body },
            headers: auth(raw), as: :json
      assert_response :unprocessable_entity
      assert_equal "validation_failed", JSON.parse(response.body)["error"]["code"]
    end

    patch "/api/v1/destinations/#{destination.id}",
          params: { destination: { rate_limit: 100, rate_limit_period: "second" } },
          headers: auth(raw), as: :json
    assert_response :ok
    json = JSON.parse(response.body)["destination"]
    assert_equal 100, json["rate_limit"]
    assert_equal "second", json["rate_limit_period"]

    patch "/api/v1/destinations/#{destination.id}",
          params: { destination: { rate_limit: 60, rate_limit_period: "minute" } },
          headers: auth(raw), as: :json
    assert_response :ok
    json = JSON.parse(response.body)["destination"]
    assert_equal 60, json["rate_limit"]
    assert_equal "minute", json["rate_limit_period"]

    patch "/api/v1/destinations/#{destination.id}", params: { destination: { rate_limit: nil } },
          headers: auth(raw), as: :json
    assert_response :ok
    json = JSON.parse(response.body)["destination"]
    assert_nil json["rate_limit"]
    assert_nil json["rate_limit_period"]

    patch "/api/v1/destinations/#{destination.id}", params: { destination: { rate_limit: 5 } },
          headers: auth(raw), as: :json
    assert_response :ok
    json = JSON.parse(response.body)["destination"]
    assert_equal 5, json["rate_limit"]
    assert_equal "second", json["rate_limit_period"]
  end

  test "a destination without a limit delivers immediately" do
    project = create_test_project!
    source, destination, connection = build_connection!(project)
    stub_request(:post, destination.url).to_return(status: 200, body: "ok")

    ingest!(source, body: '{"a":1}')
    assert_response :success

    perform_enqueued_jobs only: DeliverEventJob

    assert_equal 1, Attempt.where(connection: connection, status: "succeeded").count
    assert_no_enqueued_jobs only: DeliverEventJob
  end

  test "a burst beyond the limit queues the excess for the next window" do
    project = create_test_project!
    source, destination, connection = build_connection!(project)
    destination.update!(rate_limit: 2, rate_limit_period: "second")
    stub = stub_request(:post, destination.url).to_return(status: 200, body: "ok")

    freeze_time do
      ingest!(source, body: '{"a":1}')
      assert_response :success
      ingest!(source, body: '{"a":2}')
      assert_response :success
      ingest!(source, body: '{"a":3}')
      assert_response :success

      perform_enqueued_jobs only: DeliverEventJob

      assert_requested stub, times: 2
      assert_equal 2, Attempt.where(connection: connection).count

      jobs = enqueued_jobs.select { |j| j[:job] == DeliverEventJob }
      assert_equal 1, jobs.size
      period = 1
      expected_at = (Time.current.to_i / period * period + period).to_f
      assert_in_delta expected_at, jobs.first[:at], 0.001

      assert_equal 0, connection.reload.consecutive_failures
      assert_no_enqueued_jobs only: AlertWebhookJob

      travel 1.second
      perform_enqueued_jobs only: DeliverEventJob

      assert_requested stub, times: 3
      assert_equal 3, Attempt.where(connection: connection, status: "succeeded").count
    end
  end

  test "connections share one destination budget" do
    project = create_test_project!
    source_a, destination, connection_a = build_connection!(project)
    destination.update!(rate_limit: 1, rate_limit_period: "second")
    source_b = Source.create!(project: project, name: "S-#{SecureRandom.hex(3)}")
    Connection.create!(project: project, source: source_b, destination: destination)
    stub = stub_request(:post, destination.url).to_return(status: 200, body: "ok")

    freeze_time do
      ingest!(source_a, body: '{"a":1}')
      assert_response :success
      ingest!(source_b, body: '{"a":1}')
      assert_response :success

      perform_enqueued_jobs only: DeliverEventJob

      assert_requested stub, times: 1
      jobs = enqueued_jobs.select { |j| j[:job] == DeliverEventJob }
      assert_equal 1, jobs.size
    end
  end

  test "a replay's delivery draws from the budget and keeps its replay flag" do
    project = create_test_project!
    source, destination, connection = build_connection!(project)
    destination.update!(rate_limit: 1, rate_limit_period: "second")
    stub = stub_request(:post, destination.url).to_return(status: 200, body: "ok")

    freeze_time do
      first_event = make_event!(source)
      second_event = make_event!(source)

      DeliverEventJob.perform_later(first_event.id, connection.id)
      perform_enqueued_jobs only: DeliverEventJob

      assert_requested stub, times: 1

      assert Attempt.claim_retry!(event_id: second_event.id, connection_id: connection.id, replay: true)

      perform_enqueued_jobs only: DeliverEventJob

      assert_requested stub, times: 1
      jobs = enqueued_jobs.select { |j| j[:job] == DeliverEventJob }
      assert_equal 1, jobs.size
      assert_equal true, jobs.first[:args][2]["replay"]

      pending = Attempt.where(event: second_event, connection: connection).order(:attempt_number).last
      assert_equal "pending", pending.status
    end
  end
end
