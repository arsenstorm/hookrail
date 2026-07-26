require "test_helper"

class ConnectionRoutingTest < ActiveSupport::TestCase
  def setup
    @project = create_test_project!
    @source = Source.create!(project: @project, name: "S1")
    @destination = Destination.create!(project: @project, name: "D1", url: "https://dest.test/hook")
    @connection = Connection.create!(project: @project, source: @source, destination: @destination)
  end

  def event_for(path: "/wh", http_method: "POST", headers: {}, body: nil)
    Event.new(source: @source, path: path, http_method: http_method, headers: headers, body: body,
              received_at: Time.current)
  end

  def rule!(hash)
    @connection.update!(routing_rule: hash)
  end

  test "blank rule routes everything" do
    assert @connection.routes?(event_for)
  end

  test "exact path match and mismatch" do
    rule!("path" => "/wh")
    assert @connection.routes?(event_for(path: "/wh"))
    refute @connection.routes?(event_for(path: "/other"))
  end

  test "wildcard path matches prefix, not unrelated paths" do
    rule!("path" => "/orders/*")
    assert @connection.routes?(event_for(path: "/orders/123"))
    assert @connection.routes?(event_for(path: "/orders/1/items"))
    refute @connection.routes?(event_for(path: "/payments/1"))
  end

  test "http_method matches case-insensitively, mismatch fails" do
    rule!("http_method" => "post")
    assert @connection.routes?(event_for(http_method: "POST"))
    refute @connection.routes?(event_for(http_method: "GET"))
  end

  test "header criterion matches case-insensitive header name, value must equal" do
    rule!("headers" => { "x-github-event" => "push" })
    assert @connection.routes?(event_for(headers: { "X-Github-Event" => "push" }))
    refute @connection.routes?(event_for(headers: { "X-Github-Event" => "pull_request" }))
  end

  test "body dot path matches" do
    rule!("body" => { "type" => "invoice.paid" })
    assert @connection.routes?(event_for(body: '{"type":"invoice.paid"}'))
    refute @connection.routes?(event_for(body: '{"type":"invoice.created"}'))
  end

  test "nested dot path" do
    rule!("body" => { "data.object.status" => "active" })
    assert @connection.routes?(event_for(body: '{"data":{"object":{"status":"active"}}}'))
    refute @connection.routes?(event_for(body: '{"data":{"object":{"status":"inactive"}}}'))
  end

  test "numeric JSON value matches string criterion" do
    rule!("body" => { "count" => "42" })
    assert @connection.routes?(event_for(body: '{"count":42}'))
  end

  test "two criteria AND together" do
    rule!("path" => "/wh", "http_method" => "POST")
    assert @connection.routes?(event_for(path: "/wh", http_method: "POST"))
    refute @connection.routes?(event_for(path: "/wh", http_method: "GET"))
  end

  test "non-JSON body with body criterion returns false" do
    rule!("body" => { "type" => "invoice.paid" })
    refute @connection.routes?(event_for(body: "not json"))
  end

  test "JSON array body with body criterion returns false" do
    rule!("body" => { "type" => "invoice.paid" })
    refute @connection.routes?(event_for(body: "[1,2,3]"))
  end

  test "missing dot path returns false" do
    rule!("body" => { "data.object.status" => "active" })
    refute @connection.routes?(event_for(body: '{"data":{}}'))
  end

  test "validation: unknown key invalid" do
    @connection.routing_rule = { "bogus" => "x" }
    refute @connection.valid?
    assert_includes @connection.errors[:routing_rule].join, "unknown keys"
  end

  test "validation: headers as string invalid" do
    @connection.routing_rule = { "headers" => "not-an-object" }
    refute @connection.valid?
    assert_includes @connection.errors[:routing_rule].join, "headers must be an object"
  end

  test "validation: path as number invalid" do
    @connection.routing_rule = { "path" => 5 }
    refute @connection.valid?
    assert_includes @connection.errors[:routing_rule].join, "path must be a string"
  end

  test "blank values compacted and route everything" do
    rule!("path" => "")
    assert_equal({}, @connection.reload.routing_rule)
    assert @connection.routes?(event_for)
  end

  test "operator gt matches and fails" do
    rule!("body" => { "amount" => { "gt" => 10 } })
    assert @connection.routes?(event_for(body: '{"amount":15}'))
    refute @connection.routes?(event_for(body: '{"amount":10}'))
  end

  test "operator gte matches and fails" do
    rule!("body" => { "amount" => { "gte" => 10 } })
    assert @connection.routes?(event_for(body: '{"amount":10}'))
    refute @connection.routes?(event_for(body: '{"amount":9}'))
  end

  test "operator lt matches and fails" do
    rule!("body" => { "amount" => { "lt" => 10 } })
    assert @connection.routes?(event_for(body: '{"amount":9}'))
    refute @connection.routes?(event_for(body: '{"amount":10}'))
  end

  test "operator lte matches and fails" do
    rule!("body" => { "amount" => { "lte" => 10 } })
    assert @connection.routes?(event_for(body: '{"amount":10}'))
    refute @connection.routes?(event_for(body: '{"amount":11}'))
  end

  test "operator neq matches and fails" do
    rule!("body" => { "status" => { "neq" => "failed" } })
    assert @connection.routes?(event_for(body: '{"status":"succeeded"}'))
    refute @connection.routes?(event_for(body: '{"status":"failed"}'))
  end

  test "operator contains matches and fails" do
    rule!("body" => { "message" => { "contains" => "error" } })
    assert @connection.routes?(event_for(body: '{"message":"an error occurred"}'))
    refute @connection.routes?(event_for(body: '{"message":"all good"}'))
  end

  test "operator in matches and fails" do
    rule!("body" => { "type" => { "in" => %w[a b] } })
    assert @connection.routes?(event_for(body: '{"type":"a"}'))
    refute @connection.routes?(event_for(body: '{"type":"c"}'))
  end

  test "operator exists true matches and fails" do
    rule!("body" => { "field" => { "exists" => true } })
    assert @connection.routes?(event_for(body: '{"field":"x"}'))
    refute @connection.routes?(event_for(body: "{}"))
  end

  test "operator exists false matches and fails" do
    rule!("body" => { "field" => { "exists" => false } })
    assert @connection.routes?(event_for(body: "{}"))
    refute @connection.routes?(event_for(body: '{"field":"x"}'))
  end

  test "numeric operator does not route when actual value doesn't coerce to a number" do
    rule!("body" => { "amount" => { "gt" => 100 } })
    refute @connection.routes?(event_for(body: '{"amount":"abc"}'))
  end

  test "numeric operator does not route when the path is missing" do
    rule!("body" => { "amount" => { "gt" => 100 } })
    refute @connection.routes?(event_for(body: "{}"))
  end

  test "multiple operators in one object AND together" do
    rule!("body" => { "amount" => { "gt" => 10, "lt" => 20 } })
    assert @connection.routes?(event_for(body: '{"amount":15}'))
    refute @connection.routes?(event_for(body: '{"amount":25}'))
  end

  test "operator expression on a header criterion, case-insensitive header name" do
    rule!("headers" => { "X-Count" => { "gte" => 2 } })
    assert @connection.routes?(event_for(headers: { "x-count" => "5" }))
    refute @connection.routes?(event_for(headers: { "x-count" => "1" }))
  end

  test "scalar criteria remain exact-match after adding operators" do
    rule!("body" => { "count" => "100" }, "headers" => { "X-Github-Event" => "push" })
    assert @connection.routes?(event_for(body: '{"count":100}', headers: { "X-Github-Event" => "push" }))
    refute @connection.routes?(event_for(body: '{"count":100}', headers: { "X-Github-Event" => "pull_request" }))
  end

  test "validation: unknown operator rejected" do
    @connection.routing_rule = { "body" => { "amount" => { "between" => [ 1, 2 ] } } }
    refute @connection.valid?
    assert_includes @connection.errors[:routing_rule].join, "unknown operator: between"
  end

  test "validation: in operator must be an array" do
    @connection.routing_rule = { "body" => { "amount" => { "in" => "5" } } }
    refute @connection.valid?
    assert_includes @connection.errors[:routing_rule].join, "in must be an array"
  end

  test "validation: exists operator must be true or false" do
    @connection.routing_rule = { "body" => { "amount" => { "exists" => "yes" } } }
    refute @connection.valid?
    assert_includes @connection.errors[:routing_rule].join, "exists must be true or false"
  end

  test "validation: empty operator object rejected" do
    @connection.routing_rule = { "body" => { "amount" => {} } }
    refute @connection.valid?
    assert_includes @connection.errors[:routing_rule].join, "operator object must not be empty"
  end

  # Documented behavior: a missing body path stringifies to "" which != "failed",
  # so neq matches even though the field is absent.
  test "neq against a missing body path matches" do
    rule!("body" => { "status" => { "neq" => "failed" } })
    assert @connection.routes?(event_for(body: "{}"))
  end
end
