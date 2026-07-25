require "test_helper"

class DeduplicationFlowTest < ActionDispatch::IntegrationTest
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

  def ingest!(source, body:, headers: {})
    post ingest_path(token: source.token), params: body,
         headers: { "Content-Type" => "application/json" }.merge(headers)
  end

  test "API validates dedupe bounds and round-trips a valid config" do
    project = create_test_project!
    org = project.organization
    _key, raw = issue_key!(org)
    source, _destination, _connection = build_connection!(project)

    [
      { dedupe: { window: 0 } },
      { dedupe: { window: 86401 } },
      { dedupe: { window: 60, bogus: 1 } }
    ].each do |invalid_body|
      patch "/api/v1/sources/#{source.id}", params: { source: invalid_body },
            headers: auth(raw), as: :json
      assert_response :unprocessable_entity
      assert_equal "validation_failed", JSON.parse(response.body)["error"]["code"]
    end

    patch "/api/v1/sources/#{source.id}",
          params: { source: { dedupe: { window: 300, key: "X-Delivery-Id" } } },
          headers: auth(raw), as: :json
    assert_response :ok
    json = JSON.parse(response.body)["source"]
    assert_equal({ "window" => 300, "key" => "X-Delivery-Id" }, json["dedupe"])

    patch "/api/v1/sources/#{source.id}",
          params: { source: { dedupe: { key: "id" } } },
          headers: auth(raw), as: :json
    assert_response :ok
    json = JSON.parse(response.body)["source"]
    assert_equal({ "window" => 60, "key" => "id" }, json["dedupe"])

    patch "/api/v1/sources/#{source.id}",
          params: { source: { dedupe: {} } },
          headers: auth(raw), as: :json
    assert_response :ok
    json = JSON.parse(response.body)["source"]
    assert_nil json["dedupe"]
  end

  test "a repeated identity key within the window is marked duplicate" do
    project = create_test_project!
    source, _destination, _connection = build_connection!(project)
    source.update!(dedupe: { "window" => 60, "key" => "X-Delivery-Id" })

    ingest!(source, body: '{"a":1}', headers: { "X-Delivery-Id" => "abc" })
    assert_response :success
    ingest!(source, body: '{"a":2}', headers: { "X-Delivery-Id" => "abc" })
    assert_response :success

    events = source.events.order(:received_at, :id)
    assert_equal 2, events.count
    assert_equal false, events.first.duplicate
    assert_equal true, events.second.duplicate
    assert_equal "key:abc", events.second.dedupe_key

    ingest!(source, body: '{"a":3}', headers: { "X-Delivery-Id" => "xyz" })
    assert_response :success
    assert_equal false, source.events.order(:received_at, :id).last.duplicate

    body_keyed_source, _destination2, _connection2 = build_connection!(project)
    body_keyed_source.update!(dedupe: { "window" => 60, "key" => "id" })

    ingest!(body_keyed_source, body: '{"id":"e1","n":1}')
    assert_response :success
    ingest!(body_keyed_source, body: '{"id":"e1","n":2}')
    assert_response :success

    body_events = body_keyed_source.events.order(:received_at, :id)
    assert_equal false, body_events.first.duplicate
    assert_equal true, body_events.second.duplicate
  end

  test "byte-identical bodies are duplicates when no key is set" do
    project = create_test_project!
    source, _destination, _connection = build_connection!(project)
    source.update!(dedupe: { "window" => 60 })

    ingest!(source, body: '{"a":1}')
    assert_response :success
    ingest!(source, body: '{"a":1}')
    assert_response :success

    events = source.events.order(:received_at, :id)
    assert_equal false, events.first.duplicate
    assert_equal true, events.second.duplicate
    assert events.second.dedupe_key.start_with?("sha256:")

    ingest!(source, body: '{"a":2}')
    assert_response :success
    assert_equal false, source.events.order(:received_at, :id).last.duplicate
  end

  test "a missing or empty key value passes through as unique" do
    project = create_test_project!
    source, _destination, _connection = build_connection!(project)
    source.update!(dedupe: { "window" => 60, "key" => "X-Delivery-Id" })

    ingest!(source, body: '{"a":1}')
    assert_response :success
    ingest!(source, body: '{"a":1}')
    assert_response :success

    events = source.events.order(:received_at, :id)
    assert_equal 2, events.count
    events.each do |event|
      assert_equal false, event.duplicate
      assert_nil event.dedupe_key
    end
  end

  test "a duplicate is stored and creates zero deliveries" do
    project = create_test_project!
    source, destination, _connection = build_connection!(project)
    stub = stub_request(:post, destination.url).to_return(status: 200, body: "ok")
    source.update!(dedupe: { "window" => 60 })

    ingest!(source, body: '{"a":1}')
    assert_response :success
    ingest!(source, body: '{"a":1}')
    assert_response :success

    perform_enqueued_jobs only: DeliverEventJob

    events = source.events.order(:received_at, :id)
    assert_equal 2, events.count
    original, duplicate = events.first, events.second
    assert_equal false, original.duplicate
    assert_equal true, duplicate.duplicate

    assert_equal 1, Attempt.count
    assert_equal 1, original.attempts.count
    assert_equal 0, duplicate.attempts.count
    assert_requested stub, times: 1
  end

  test "the same identity after the window is a new event" do
    project = create_test_project!
    source, destination, connection = build_connection!(project)
    stub_request(:post, destination.url).to_return(status: 200, body: "ok")
    source.update!(dedupe: { "window" => 60 })

    freeze_time do
      ingest!(source, body: '{"a":1}')
      assert_response :success

      travel 61.seconds

      ingest!(source, body: '{"a":1}')
      assert_response :success

      events = source.events.order(:received_at, :id)
      assert_equal 2, events.count
      assert_equal false, events.second.duplicate

      perform_enqueued_jobs only: DeliverEventJob

      assert_equal 2, Attempt.where(connection: connection, status: "succeeded").count
    end
  end

  test "dedupe runs before routing rules" do
    project = create_test_project!
    source, _destination, connection = build_connection!(project)
    connection.update!(routing_rule: { "path" => "/never" })
    source.update!(dedupe: { "window" => 60 })

    ingest!(source, body: '{"a":1}')
    assert_response :success
    ingest!(source, body: '{"a":1}')
    assert_response :success

    events = source.events.order(:received_at, :id)
    assert_equal 2, events.count
    first_event, second_event = events.first, events.second

    assert_equal 0, first_event.attempts.count
    assert_equal false, first_event.duplicate
    assert_equal true, second_event.duplicate
  end

  test "replay bypasses dedupe in both directions" do
    project = create_test_project!
    source, destination, connection = build_connection!(project)
    stub_request(:post, destination.url).to_return(status: 200, body: "ok")
    source.update!(dedupe: { "window" => 60 })

    ingest!(source, body: '{"a":1}')
    assert_response :success
    ingest!(source, body: '{"a":1}')
    assert_response :success

    perform_enqueued_jobs only: DeliverEventJob

    events = source.events.order(:received_at, :id)
    original_event, duplicate_event = events.first, events.second
    assert_equal false, original_event.duplicate
    assert_equal true, duplicate_event.duplicate
    assert_equal 1, original_event.attempts.succeeded.count
    assert_equal 0, duplicate_event.attempts.count

    assert Attempt.claim_retry!(event_id: duplicate_event.id, connection_id: connection.id, replay: true)
    perform_enqueued_jobs only: DeliverEventJob
    assert_equal 1, duplicate_event.attempts.succeeded.count

    assert Attempt.claim_retry!(event_id: original_event.id, connection_id: connection.id, replay: true)
    perform_enqueued_jobs only: DeliverEventJob
    assert_equal 2, original_event.attempts.succeeded.count
  end

  test "API create accepts dedupe and show returns it" do
    project = create_test_project!
    org = project.organization
    _key, raw = issue_key!(org)

    post "/api/v1/sources", params: { source: { name: "Deduped", dedupe: { window: 120, key: "X-Id" } } },
         headers: auth(raw), as: :json
    assert_response :created
    json = JSON.parse(response.body)["source"]
    assert_equal({ "window" => 120, "key" => "X-Id" }, json["dedupe"])
    source_id = json["id"]

    get "/api/v1/sources/#{source_id}", headers: auth(raw), as: :json
    assert_response :ok
    assert_equal({ "window" => 120, "key" => "X-Id" }, JSON.parse(response.body)["source"]["dedupe"])

    post "/api/v1/sources", params: { source: { name: "Plain" } }, headers: auth(raw), as: :json
    assert_response :created
    plain_id = JSON.parse(response.body)["source"]["id"]

    get "/api/v1/sources/#{plain_id}", headers: auth(raw), as: :json
    assert_response :ok
    assert_nil JSON.parse(response.body)["source"]["dedupe"]
  end
end
