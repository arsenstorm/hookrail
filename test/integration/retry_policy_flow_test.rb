require "test_helper"

class RetryPolicyFlowTest < ActionDispatch::IntegrationTest
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

  test "API validates retry policy bounds and round-trips a valid one" do
    project = create_test_project!
    org = project.organization
    _key, raw = issue_key!(org)
    _source, _destination, connection = build_connection!(project)

    [
      { strategy: "linear", interval: 60, max_attempts: 3, bogus: 1 },
      { strategy: "sometimes", interval: 60, max_attempts: 3 },
      { strategy: "linear", interval: 0, max_attempts: 3 },
      { strategy: "linear", interval: 60, max_attempts: 51 },
      { strategy: "exponential", interval: 3600, max_attempts: 20 }
    ].each do |invalid_policy|
      patch "/api/v1/connections/#{connection.id}", params: { connection: { retry_policy: invalid_policy } },
            headers: auth(raw), as: :json
      assert_response :unprocessable_entity
      assert_equal "validation_failed", JSON.parse(response.body)["error"]["code"]
    end

    patch "/api/v1/connections/#{connection.id}",
          params: { connection: { retry_policy: { strategy: "linear", interval: 60, max_attempts: 3 } } },
          headers: auth(raw), as: :json
    assert_response :ok
    assert_equal({ "strategy" => "linear", "interval" => 60, "max_attempts" => 3 },
                 JSON.parse(response.body)["connection"]["retry_policy"])

    patch "/api/v1/connections/#{connection.id}", params: { connection: { retry_policy: {} } },
          headers: auth(raw), as: :json
    assert_response :ok
    assert_nil JSON.parse(response.body)["connection"]["retry_policy"]
  end

  test "a connection without a policy keeps the default schedule" do
    project = create_test_project!
    source, destination, connection = build_connection!(project)
    event = make_event!(source)
    stub_request(:post, destination.url).to_return(status: 500, body: "err")

    freeze_time do
      DeliverEventJob.perform_now(event.id, connection.id)

      jobs = enqueued_jobs.select { |j| j[:job] == DeliverEventJob }
      assert_equal 1, jobs.size
      assert_equal 10.seconds.from_now.to_f, jobs.first[:at]
    end

    latest = Attempt.where(connection: connection).order(:attempt_number).last
    assert_equal "failed", latest.status
  end

  test "linear policy spaces retries by the interval and dies at max_attempts" do
    project = create_test_project!
    source, destination, connection = build_connection!(project)
    connection.update!(retry_policy: { strategy: "linear", interval: 60, max_attempts: 3 })
    event = make_event!(source)
    stub = stub_request(:post, destination.url).to_return(status: 500, body: "err")

    freeze_time do
      DeliverEventJob.perform_now(event.id, connection.id)
      jobs = enqueued_jobs.select { |j| j[:job] == DeliverEventJob }
      assert_equal 1, jobs.size
      assert_equal 60.seconds.from_now.to_f, jobs.first[:at]
      clear_enqueued_jobs

      DeliverEventJob.perform_now(event.id, connection.id, retry_count: 1)
      jobs = enqueued_jobs.select { |j| j[:job] == DeliverEventJob }
      assert_equal 1, jobs.size
      assert_equal 60.seconds.from_now.to_f, jobs.first[:at]
      clear_enqueued_jobs

      DeliverEventJob.perform_now(event.id, connection.id, retry_count: 2)
      assert_no_enqueued_jobs only: DeliverEventJob
    end

    latest = Attempt.where(connection: connection).order(:attempt_number).last
    assert_equal "dead", latest.status
    assert_requested stub, times: 3
  end

  test "exponential policy doubles the gap each retry" do
    project = create_test_project!
    source, destination, connection = build_connection!(project)
    connection.update!(retry_policy: { strategy: "exponential", interval: 10, max_attempts: 4 })
    event = make_event!(source)
    stub_request(:post, destination.url).to_return(status: 500, body: "err")

    freeze_time do
      DeliverEventJob.perform_now(event.id, connection.id)
      jobs = enqueued_jobs.select { |j| j[:job] == DeliverEventJob }
      assert_equal 1, jobs.size
      assert_equal 10.seconds.from_now.to_f, jobs.first[:at]
      clear_enqueued_jobs

      DeliverEventJob.perform_now(event.id, connection.id, retry_count: 1)
      jobs = enqueued_jobs.select { |j| j[:job] == DeliverEventJob }
      assert_equal 1, jobs.size
      assert_equal 20.seconds.from_now.to_f, jobs.first[:at]
      clear_enqueued_jobs

      DeliverEventJob.perform_now(event.id, connection.id, retry_count: 2)
      jobs = enqueued_jobs.select { |j| j[:job] == DeliverEventJob }
      assert_equal 1, jobs.size
      assert_equal 40.seconds.from_now.to_f, jobs.first[:at]
      clear_enqueued_jobs

      DeliverEventJob.perform_now(event.id, connection.id, retry_count: 3)
      assert_no_enqueued_jobs only: DeliverEventJob
    end

    latest = Attempt.where(connection: connection).order(:attempt_number).last
    assert_equal "dead", latest.status
  end

  test "transformation failures follow the policy too" do
    project = create_test_project!
    source, _destination, connection = build_connection!(project)
    connection.update!(retry_policy: { strategy: "linear", interval: 30, max_attempts: 2 },
                        transformation: 'function transform(request) { throw new Error("boom") }')
    event = make_event!(source)

    freeze_time do
      DeliverEventJob.perform_now(event.id, connection.id)
      latest = Attempt.where(connection: connection).order(:attempt_number).last
      assert_equal "failed", latest.status
      assert latest.error.start_with?("TransformationError:")
      jobs = enqueued_jobs.select { |j| j[:job] == DeliverEventJob }
      assert_equal 1, jobs.size
      assert_equal 30.seconds.from_now.to_f, jobs.first[:at]
      clear_enqueued_jobs

      DeliverEventJob.perform_now(event.id, connection.id, retry_count: 1)
      latest = Attempt.where(connection: connection).order(:attempt_number).last
      assert_equal "dead", latest.status
      assert_no_enqueued_jobs only: DeliverEventJob
    end
  end

  test "a manual retry starts a fresh chain under the policy" do
    project = create_test_project!
    source, destination, connection = build_connection!(project)
    connection.update!(retry_policy: { strategy: "linear", interval: 60, max_attempts: 2 })
    event = make_event!(source)
    stub = stub_request(:post, destination.url).to_return(status: 500, body: "err")

    DeliverEventJob.perform_now(event.id, connection.id)
    DeliverEventJob.perform_now(event.id, connection.id, retry_count: 1)

    assert_equal 2, Attempt.where(event: event, connection: connection).count
    assert_equal "dead", Attempt.where(connection: connection).order(:attempt_number).last.status
    clear_enqueued_jobs

    assert Attempt.claim_retry!(event_id: event.id, connection_id: connection.id)

    while enqueued_jobs.any? { |j| j[:job] == DeliverEventJob }
      perform_enqueued_jobs only: DeliverEventJob
    end

    assert_equal 4, Attempt.where(event: event, connection: connection).count
    assert_equal "dead", Attempt.where(connection: connection).order(:attempt_number).last.status
    assert_requested stub, times: 4
  end
end
