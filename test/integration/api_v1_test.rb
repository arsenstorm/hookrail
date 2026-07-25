require "test_helper"

class ApiV1Test < ActionDispatch::IntegrationTest
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

  # An event on `source` with an attempt of `status` on `connection`. Returns the event.
  def make_event!(source, connection, status:)
    event = Event.create!(source: source, http_method: "POST", path: "/wh", received_at: Time.current,
                          headers: { "Content-Type" => "application/json" }, body: %({"x":1}))
    Attempt.create!(event: event, connection: connection, attempt_number: 1,
                    attempted_at: Time.current, status: status)
    event
  end

  test "full pipeline lifecycle via API only" do
    project = create_test_project!
    org = project.organization
    _key, raw = issue_key!(org)

    post "/api/v1/sources", params: { source: { name: "My Source" } }, headers: auth(raw), as: :json
    assert_response :created
    source_json = JSON.parse(response.body)["source"]
    token = source_json["token"]
    assert token.present?

    post "/api/v1/destinations", params: { destination: { name: "My Dest", url: "https://dest.test/hook" } },
                                  headers: auth(raw), as: :json
    assert_response :created
    destination_json = JSON.parse(response.body)["destination"]

    post "/api/v1/connections",
         params: { connection: { source_id: source_json["id"], destination_id: destination_json["id"] } },
         headers: auth(raw), as: :json
    assert_response :created

    post "/ingest/#{token}", params: '{"hello":"world"}', headers: { "Content-Type" => "application/json" }
    assert_response :success

    get "/api/v1/events", params: { source_id: source_json["id"] }, headers: auth(raw)
    assert_response :ok
    events = JSON.parse(response.body)["events"]
    assert_equal 1, events.size
    assert_equal '{"hello":"world"}', events.first["body"]
  end

  test "source update sets verification and never returns the secret" do
    project = create_test_project!
    org = project.organization
    _key, raw = issue_key!(org)
    source = Source.create!(project: project, name: "S1")

    patch "/api/v1/sources/#{source.id}",
          params: { source: { verification_secret: "super-secret-value", verification_header: "X-Sig" } },
          headers: auth(raw), as: :json
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal true, body["source"]["verification_enabled"]
    assert_not_includes response.body, "super-secret-value"
  end

  test "source destroy removes it from the index" do
    project = create_test_project!
    org = project.organization
    _key, raw = issue_key!(org)
    source = Source.create!(project: project, name: "S1")

    delete "/api/v1/sources/#{source.id}", headers: auth(raw)
    assert_response :no_content

    get "/api/v1/sources", headers: auth(raw)
    assert_equal [], JSON.parse(response.body)["sources"]
  end

  test "destination update and destroy" do
    project = create_test_project!
    org = project.organization
    _key, raw = issue_key!(org)
    destination = Destination.create!(project: project, name: "D1", url: "https://old.test/hook")

    patch "/api/v1/destinations/#{destination.id}",
          params: { destination: { url: "https://new.test/hook" } }, headers: auth(raw), as: :json
    assert_response :ok
    assert_equal "https://new.test/hook", JSON.parse(response.body)["destination"]["url"]

    delete "/api/v1/destinations/#{destination.id}", headers: auth(raw)
    assert_response :no_content

    get "/api/v1/destinations", headers: auth(raw)
    assert_equal [], JSON.parse(response.body)["destinations"]
  end

  test "connection update and destroy" do
    project = create_test_project!
    org = project.organization
    _key, raw = issue_key!(org)
    _source, connection = build_connection!(project)

    patch "/api/v1/connections/#{connection.id}",
          params: { connection: { active: false } }, headers: auth(raw), as: :json
    assert_response :ok
    assert_equal false, JSON.parse(response.body)["connection"]["active"]

    delete "/api/v1/connections/#{connection.id}", headers: auth(raw)
    assert_response :no_content

    get "/api/v1/connections", headers: auth(raw)
    assert_equal [], JSON.parse(response.body)["connections"]
  end

  test "validation error shape on blank name" do
    project = create_test_project!
    org = project.organization
    _key, raw = issue_key!(org)

    post "/api/v1/sources", params: { source: { name: "" } }, headers: auth(raw), as: :json
    assert_response :unprocessable_entity
    assert_equal "validation_failed", JSON.parse(response.body)["error"]["code"]
  end

  test "cross-org access to another org's source 404s" do
    project_a = create_test_project!
    source_a = Source.create!(project: project_a, name: "S-A")

    project_b = create_test_project!
    _key_b, raw_b = issue_key!(project_b.organization)

    get "/api/v1/sources/#{source_a.id}", headers: auth(raw_b)
    assert_response :not_found
    assert_equal "not_found", JSON.parse(response.body)["error"]["code"]

    patch "/api/v1/sources/#{source_a.id}", params: { source: { name: "hijacked" } },
                                             headers: auth(raw_b), as: :json
    assert_response :not_found
    assert_equal "not_found", JSON.parse(response.body)["error"]["code"]

    delete "/api/v1/sources/#{source_a.id}", headers: auth(raw_b)
    assert_response :not_found
    assert_equal "not_found", JSON.parse(response.body)["error"]["code"]
  end

  test "cross-org foreign ids on connection create are rejected" do
    project_a = create_test_project!
    source_a = Source.create!(project: project_a, name: "S-A")
    destination_a = Destination.create!(project: project_a, name: "D-A", url: "https://a.test/hook")

    project_b = create_test_project!
    _key_b, raw_b = issue_key!(project_b.organization)

    assert_no_difference "Connection.count" do
      post "/api/v1/connections",
           params: { connection: { source_id: source_a.id, destination_id: destination_a.id } },
           headers: auth(raw_b), as: :json
    end
    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "validation_failed", body["error"]["code"]
    assert_match "must exist", body["error"]["message"]
  end

  test "events filters and cursor" do
    project = create_test_project!
    org = project.organization
    _key, raw = issue_key!(org)
    source, connection = build_connection!(project)

    make_event!(source, connection, status: :failed)
    make_event!(source, connection, status: :succeeded)
    Event.create!(source: source, http_method: "POST", path: "/wh", received_at: Time.current,
                  headers: {}, body: "{}")

    get "/api/v1/events", params: { status: "failed" }, headers: auth(raw)
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal 1, body["events"].size
    assert_nil body["next_cursor"]
  end

  test "attempts read" do
    project = create_test_project!
    org = project.organization
    _key, raw = issue_key!(org)
    source, connection = build_connection!(project)
    event = Event.create!(source: source, http_method: "POST", path: "/wh", received_at: Time.current,
                          headers: {}, body: "{}")
    Attempt.create!(event: event, connection: connection, attempt_number: 1,
                    attempted_at: Time.current, status: :failed)
    Attempt.create!(event: event, connection: connection, attempt_number: 2,
                    attempted_at: Time.current, status: :succeeded)

    get "/api/v1/events/#{event.id}/attempts", headers: auth(raw)
    assert_response :ok
    attempts = JSON.parse(response.body)["attempts"]
    assert_equal 2, attempts.size
    assert_equal [ 1, 2 ], attempts.map { |a| a["attempt_number"] }
    assert_equal [ "failed", "succeeded" ], attempts.map { |a| a["status"] }
  end

  test "single retry and bulk retry" do
    project = create_test_project!
    org = project.organization
    _key, raw = issue_key!(org)
    source, connection = build_connection!(project)

    failed_event = make_event!(source, connection, status: :failed)

    assert_enqueued_jobs(1, only: DeliverEventJob) do
      post "/api/v1/events/#{failed_event.id}/retries",
           params: { connection_id: connection.id }, headers: auth(raw), as: :json
    end
    assert_response :accepted

    succeeded_event = make_event!(source, connection, status: :succeeded)
    post "/api/v1/events/#{succeeded_event.id}/retries",
         params: { connection_id: connection.id }, headers: auth(raw), as: :json
    assert_response :unprocessable_entity
    assert_equal "not_retryable", JSON.parse(response.body)["error"]["code"]

    other_source, other_connection = build_connection!(project)
    make_event!(other_source, other_connection, status: :failed)
    make_event!(other_source, other_connection, status: :failed)
    make_event!(other_source, other_connection, status: :succeeded)

    assert_enqueued_jobs(2, only: DeliverEventJob) do
      post "/api/v1/events/bulk_retry", params: { source_id: other_source.id }, headers: auth(raw), as: :json
    end
    assert_response :accepted
    assert_equal({ "enqueued" => 2 }, JSON.parse(response.body))
  end
end
