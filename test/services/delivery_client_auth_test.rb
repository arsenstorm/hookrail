require "test_helper"

class DeliveryClientAuthTest < ActiveSupport::TestCase
  def setup
    @project = create_test_project!
    @source = Source.create!(project: @project, name: "S1")
    @destination = Destination.create!(project: @project, name: "D1", url: "https://dest.test/hook")
  end

  def event_for(headers: {})
    Event.new(source: @source, path: "/wh", http_method: "POST", headers: headers, body: "{}",
              received_at: Time.current)
  end

  test "no auth configured leaves headers without Authorization" do
    payload = Delivery::Client.payload_for(event: event_for, destination: @destination)
    assert_not payload[:headers].key?("Authorization")
  end

  test "bearer auth sets Authorization header" do
    @destination.update!(auth: { type: "bearer", token: "tok" })
    payload = Delivery::Client.payload_for(event: event_for, destination: @destination)
    assert_equal "Bearer tok", payload[:headers]["Authorization"]
  end

  test "basic auth sets Authorization header" do
    @destination.update!(auth: { type: "basic", username: "u", password: "p" })
    payload = Delivery::Client.payload_for(event: event_for, destination: @destination)
    assert_equal "Basic #{Base64.strict_encode64("u:p")}", payload[:headers]["Authorization"]
  end

  test "configured auth overrides a manually set Authorization header" do
    @destination.update!(headers: { "Authorization" => "Bearer stale" }, auth: { type: "bearer", token: "fresh" })
    payload = Delivery::Client.payload_for(event: event_for, destination: @destination)
    assert_equal "Bearer fresh", payload[:headers]["Authorization"]
  end
end
