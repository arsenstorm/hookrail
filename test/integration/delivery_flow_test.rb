require "test_helper"

class DeliveryFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def setup
    @source = Source.create!(name: "Src")
    @destination = Destination.create!(name: "Dest", url: "https://example.test/hook")
    @connection = Connection.create!(source: @source, destination: @destination, active: true)
  end

  def ingest!(body: '{"a":1}', headers: { "Content-Type" => "application/json" })
    perform_enqueued_jobs do
      post "/ingest/#{@source.token}", params: body, headers: headers
    end
  end

  test "delivers a received event to an active connection" do
    stub = stub_request(:post, @destination.url).to_return(status: 200, body: "ok")
    ingest!
    assert_requested stub, times: 1
    attempts = Attempt.where(connection: @connection)
    assert_equal 1, attempts.count
    assert attempts.first.succeeded?
    assert_equal 200, attempts.first.response_status
  end

  test "retries with backoff then marks dead after the final attempt" do
    stub_request(:post, @destination.url).to_return(status: 500, body: "err")
    ingest!
    attempts = Attempt.where(connection: @connection).order(:attempt_number)
    assert_equal DeliverEventJob::MAX_ATTEMPTS, attempts.count
    assert_equal (1..DeliverEventJob::MAX_ATTEMPTS).to_a, attempts.map(&:attempt_number)
    assert attempts.last.dead?
    assert(attempts[0...-1].all?(&:failed?))
    assert_equal [ 10.seconds, 1.minute, 5.minutes, 30.minutes, 2.hours ], DeliverEventJob::BACKOFF
  end

  test "treats a timeout as a retryable failure" do
    stub_request(:post, @destination.url).to_timeout
    ingest!
    attempts = Attempt.where(connection: @connection).order(:attempt_number)
    assert_equal DeliverEventJob::MAX_ATTEMPTS, attempts.count
    assert attempts.first.failed?
    assert_match(/timeout|Timeout|ExecutionExpired/, attempts.first.error.to_s)
  end

  test "signs the forwarded payload with the destination secret" do
    captured = nil
    stub_request(:post, @destination.url)
      .with { |req| captured = req; true }
      .to_return(status: 200)
    ingest!(body: '{"x":9}')
    ts = captured.headers["X-Hookrail-Timestamp"]
    expected = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", @destination.signing_secret, "#{ts}.#{captured.body}")
    assert_equal expected, captured.headers["X-Hookrail-Signature"]
  end

  test "forwards original inbound headers including content-type, dropping hop-by-hop" do
    captured = nil
    stub_request(:post, @destination.url)
      .with { |req| captured = req; true }
      .to_return(status: 200)
    ingest!(body: '{"a":1}', headers: { "Content-Type" => "application/json", "X-Custom" => "keep-me" })
    assert_equal "application/json", captured.headers["Content-Type"]
    assert_equal "keep-me", captured.headers["X-Custom"]
    # Host is the destination's host, not the inbound request's (hop-by-hop dropped).
    assert_equal "example.test", captured.headers["Host"]
  end

  test "fans out to every active connection" do
    dest2 = Destination.create!(name: "Dest2", url: "https://example.test/hook2")
    Connection.create!(source: @source, destination: dest2, active: true)
    s1 = stub_request(:post, @destination.url).to_return(status: 200)
    s2 = stub_request(:post, dest2.url).to_return(status: 200)
    ingest!
    assert_requested s1, times: 1
    assert_requested s2, times: 1
    assert_equal 2, Attempt.succeeded.count
  end
end
