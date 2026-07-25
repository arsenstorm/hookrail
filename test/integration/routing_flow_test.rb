require "test_helper"

class RoutingFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "fan-out delivers only to connections whose rule matches" do
    project = create_test_project!
    source = Source.create!(project: project, name: "S1")
    dest_a = Destination.create!(project: project, name: "D-A", url: "https://a.test/hook")
    dest_b = Destination.create!(project: project, name: "D-B", url: "https://b.test/hook")
    conn_a = Connection.create!(project: project, source: source, destination: dest_a)
    conn_b = Connection.create!(project: project, source: source, destination: dest_b,
                                 routing_rule: { "body" => { "type" => "invoice.paid" } })

    assert_enqueued_jobs 2 do
      post "/ingest/#{source.token}", params: '{"type":"invoice.paid"}',
                                       headers: { "Content-Type" => "application/json" }
    end
    assert_response :ok
    event = source.events.last
    assert_enqueued_with(job: DeliverEventJob, args: [ event.id, conn_a.id ])
    assert_enqueued_with(job: DeliverEventJob, args: [ event.id, conn_b.id ])

    clear_enqueued_jobs

    assert_enqueued_jobs 1 do
      post "/ingest/#{source.token}", params: '{"type":"invoice.created"}',
                                       headers: { "Content-Type" => "application/json" }
    end
    assert_response :ok
    other_event = source.events.last
    assert_enqueued_with(job: DeliverEventJob, args: [ other_event.id, conn_a.id ])
  end

  test "all connections rule-mismatched enqueues nothing but stores the event" do
    project = create_test_project!
    source = Source.create!(project: project, name: "S1")
    destination = Destination.create!(project: project, name: "D1", url: "https://d.test/hook")
    Connection.create!(project: project, source: source, destination: destination,
                        routing_rule: { "path" => "/only-this" })

    assert_enqueued_jobs 0 do
      post "/ingest/#{source.token}", params: "{}", headers: { "Content-Type" => "application/json" }
    end
    assert_response :ok
    event = source.events.last
    assert_includes Event.with_delivery_status("undelivered"), event
  end

  test "non-JSON body against a body rule skips that connection but stores the event" do
    project = create_test_project!
    source = Source.create!(project: project, name: "S1")
    destination = Destination.create!(project: project, name: "D1", url: "https://d.test/hook")
    Connection.create!(project: project, source: source, destination: destination,
                        routing_rule: { "body" => { "type" => "invoice.paid" } })

    assert_enqueued_jobs 0 do
      post "/ingest/#{source.token}", params: "not json", headers: { "Content-Type" => "text/plain" }
    end
    assert_response :ok
    assert_equal "not json", source.events.last.body
  end

  test "API round-trip: patch routing_rule, get returns it, next ingest respects it" do
    project = create_test_project!
    org = project.organization
    _key, raw = ApiKey.issue!(organization: org, name: "test")
    source = Source.create!(project: project, name: "S1")
    destination = Destination.create!(project: project, name: "D1", url: "https://d.test/hook")
    connection = Connection.create!(project: project, source: source, destination: destination)
    headers = { "Authorization" => "Bearer #{raw}" }

    patch "/api/v1/connections/#{connection.id}",
          params: { connection: { routing_rule: { "path" => "/only-this" } } }, headers: headers, as: :json
    assert_response :ok
    assert_equal({ "path" => "/only-this" }, JSON.parse(response.body)["connection"]["routing_rule"])

    get "/api/v1/connections/#{connection.id}", headers: headers
    assert_response :ok
    assert_equal({ "path" => "/only-this" }, JSON.parse(response.body)["connection"]["routing_rule"])

    assert_enqueued_jobs 0 do
      post "/ingest/#{source.token}", params: "{}", headers: { "Content-Type" => "application/json" }
    end
  end

  test "API rejects an unknown routing_rule key with 422 validation_failed" do
    project = create_test_project!
    org = project.organization
    _key, raw = ApiKey.issue!(organization: org, name: "test")
    source = Source.create!(project: project, name: "S1")
    destination = Destination.create!(project: project, name: "D1", url: "https://d.test/hook")
    connection = Connection.create!(project: project, source: source, destination: destination)

    patch "/api/v1/connections/#{connection.id}",
          params: { connection: { routing_rule: { "bogus" => "x" } } },
          headers: { "Authorization" => "Bearer #{raw}" }, as: :json
    assert_response :unprocessable_entity
    assert_equal "validation_failed", JSON.parse(response.body)["error"]["code"]
  end
end
