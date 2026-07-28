require "test_helper"

# End-to-end version of the guard: a destination that resolves somewhere
# private must fail as a delivery, without a request leaving the process and
# without a response body landing on the attempt for the tenant to read.
class Delivery::SsrfDeliveryTest < ActiveSupport::TestCase
  setup do
    @project = create_test_project!
    @source = @project.sources.create!(name: "In")
    @event = @source.events.create!(
      http_method: "POST", path: "/hook", headers: {}, body: '{"ok":true}',
      received_at: Time.current
    )
  end

  def deliver_to(url, resolves_to: nil)
    destination = @project.destinations.new(name: "Target", kind: "http", url: url)
    destination.save!(validate: resolves_to.nil?)

    if resolves_to
      previous = Delivery::AddressGuard.resolver
      Delivery::AddressGuard.resolver = ->(_host) { resolves_to }
    end
    Delivery::Client.deliver(event: @event, destination: destination)
  ensure
    Delivery::AddressGuard.resolver = previous if resolves_to
  end

  test "a destination resolving to cloud metadata is not delivered" do
    result = deliver_to("https://metadata.example/latest/meta-data/",
                        resolves_to: [ "169.254.169.254" ])

    assert_nil result.status
    assert_nil result.body_excerpt
    assert_match "BlockedError", result.error
    assert_not_requested :post, "https://metadata.example/latest/meta-data/"
  end

  test "a destination resolving to loopback is not delivered" do
    result = deliver_to("https://rebind.example/x", resolves_to: [ "127.0.0.1" ])

    assert_nil result.status
    assert_match "blocked address", result.error
  end

  test "a public destination still delivers" do
    stub_request(:post, "https://hooks.example/x").to_return(status: 200, body: "ok")
    result = deliver_to("https://hooks.example/x")

    assert_equal 200, result.status
    assert_equal "ok", result.body_excerpt
  end

  test "the form rejects a private destination url" do
    destination = @project.destinations.new(name: "Local", kind: "http", url: "http://127.0.0.1:3000/x")

    assert_not destination.valid?
    assert_match(/not a public address/, destination.errors[:url].join)
  end

  test "the form rejects a non-http scheme" do
    destination = @project.destinations.new(name: "File", kind: "http", url: "file:///etc/passwd")

    assert_not destination.valid?
    assert_match(/http/, destination.errors[:url].join)
  end
end
