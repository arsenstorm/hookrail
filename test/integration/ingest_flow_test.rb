require "test_helper"

class IngestFlowTest < ActionDispatch::IntegrationTest
  test "stores an incoming webhook and returns 200" do
    source = Source.create!(name: "Test Source")

    assert_difference -> { source.events.count }, 1 do
      post "/ingest/#{source.token}?foo=bar",
        params: '{"hello":"world"}',
        headers: { "Content-Type" => "application/json", "X-Sig" => "abc" }
    end

    assert_response :ok
    event = source.events.last
    assert_equal "POST", event.http_method
    assert_equal "foo=bar", event.query_string
    assert_equal "abc", event.headers["X-Sig"]
    assert_equal '{"hello":"world"}', event.body
  end

  test "any HTTP method is accepted" do
    source = Source.create!(name: "Test Source")

    get "/ingest/#{source.token}"

    assert_response :ok
    assert_equal "GET", source.events.last.http_method
  end

  test "unknown token returns 404 and stores nothing" do
    assert_no_difference -> { Event.count } do
      post "/ingest/does-not-exist", params: "{}"
    end

    assert_response :not_found
  end
end
