require "test_helper"

class AlertWebhookFlowTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper
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

  def alert_webhook_jobs
    enqueued_jobs.select { |j| j[:job] == AlertWebhookJob }
  end

  test "five consecutive failures enqueue one email and one alert webhook job; performing it posts a signed payload" do
    project = create_test_project!
    org = project.organization
    org.update!(alert_webhook_url: "https://alerts.test/hook")
    _source, destination, connection = build_connection!(project)

    captured = nil
    stub = stub_request(:post, "https://alerts.test/hook")
      .with { |req| captured = req; true }
      .to_return(status: 200, body: "ok")

    assert_enqueued_emails 1 do
      assert_enqueued_jobs 1, only: AlertWebhookJob do
        5.times { connection.record_delivery_failure }
      end
    end

    perform_enqueued_jobs only: AlertWebhookJob

    assert_requested stub
    body = JSON.parse(captured.body)
    assert_equal "connection.unhealthy", body["type"]
    assert Time.iso8601(body["occurred_at"])
    data = body["data"]
    assert_equal connection.source.name, data["source"]
    assert_equal destination.name, data["destination"]
    assert_equal 5, data["consecutive_failures"]
    assert Time.iso8601(data["unhealthy_since"])

    timestamp = captured.headers["X-Hookrail-Timestamp"]
    expected_signature =
      "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", org.reload.alert_webhook_secret, "#{timestamp}.#{captured.body}")}"
    assert_equal expected_signature, captured.headers["X-Hookrail-Signature"]
  end

  test "recovery after unhealthy enqueues a connection.recovered webhook job" do
    project = create_test_project!
    org = project.organization
    org.update!(alert_webhook_url: "https://alerts.test/hook")
    _source, destination, connection = build_connection!(project)
    5.times { connection.record_delivery_failure }

    assert_enqueued_jobs 1, only: AlertWebhookJob do
      connection.record_delivery_success
    end

    _org_id, type, data, occurred_at = alert_webhook_jobs.last[:args]
    assert_equal "connection.recovered", type
    assert_equal connection.source.name, data["source"]
    assert_equal destination.name, data["destination"]
    assert Time.iso8601(occurred_at)
  end

  test "creating a quarantined webhook enqueues a webhook.quarantined job" do
    project = create_test_project!
    org = project.organization
    org.update!(alert_webhook_url: "https://alerts.test/hook")
    source, = build_connection!(project)

    assert_enqueued_jobs 1, only: AlertWebhookJob do
      source.quarantined_webhooks.create!(
        http_method: "POST", headers: {}, reason: "signature mismatch", received_at: Time.current
      )
    end

    _org_id, type, data, occurred_at = alert_webhook_jobs.last[:args]
    assert_equal "webhook.quarantined", type
    assert_equal source.name, data["source"]
    assert_equal "signature mismatch", data["reason"]
    assert Time.iso8601(data["received_at"])
    assert Time.iso8601(occurred_at)
  end

  test "an org without an alert webhook url only enqueues the email" do
    project = create_test_project!
    _source, _destination, connection = build_connection!(project)

    assert_enqueued_emails 1 do
      assert_no_enqueued_jobs only: AlertWebhookJob do
        5.times { connection.record_delivery_failure }
      end
    end
  end

  test "receiver failures are bounded and silent" do
    project = create_test_project!
    org = project.organization
    org.owner.update!(email: "owner@example.com")
    org.update!(alert_webhook_url: "https://alerts.test/hook")
    _source, _destination, connection = build_connection!(project)

    stub = stub_request(:post, "https://alerts.test/hook").to_return(status: 500)

    assert_emails 1 do
      perform_enqueued_jobs do
        5.times { connection.record_delivery_failure }
      end
    end

    assert_requested stub, times: AlertWebhookJob::MAX_ATTEMPTS
    assert_no_enqueued_jobs only: AlertWebhookJob
  end

  test "secret lifecycle: generated on url set, kept across url changes, cleared on removal" do
    project = create_test_project!
    org = project.organization
    assert_nil org.alert_webhook_secret

    org.update!(alert_webhook_url: "https://alerts.test/hook")
    assert_match(/\A[0-9a-f]{48}\z/, org.alert_webhook_secret)
    original_secret = org.alert_webhook_secret

    org.update!(alert_webhook_url: "https://alerts2.test/hook")
    assert_equal original_secret, org.alert_webhook_secret

    org.update!(alert_webhook_url: nil)
    assert_nil org.alert_webhook_secret

    assert_not org.update(alert_webhook_url: "not a url")
    assert org.errors[:alert_webhook_url].any?
  end

  test "API: show, update, invalid update, and destroy of the alert webhook" do
    project = create_test_project!
    org = project.organization
    _key, raw = issue_key!(org)

    get "/api/v1/alert_webhook", headers: auth(raw)
    assert_response :ok
    body = JSON.parse(response.body)
    assert_nil body["alert_webhook"]["url"]
    assert_nil body["alert_webhook"]["secret"]

    put "/api/v1/alert_webhook", params: { alert_webhook: { url: "https://alerts.test/hook" } },
        headers: auth(raw), as: :json
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal "https://alerts.test/hook", body["alert_webhook"]["url"]
    assert_not_nil body["alert_webhook"]["secret"]

    put "/api/v1/alert_webhook", params: { alert_webhook: { url: "not a url" } }, headers: auth(raw), as: :json
    assert_response :unprocessable_entity
    assert_equal "validation_failed", JSON.parse(response.body)["error"]["code"]

    delete "/api/v1/alert_webhook", headers: auth(raw)
    assert_response :no_content

    get "/api/v1/alert_webhook", headers: auth(raw)
    assert_response :ok
    body = JSON.parse(response.body)
    assert_nil body["alert_webhook"]["url"]
    assert_nil body["alert_webhook"]["secret"]
  end

  test "Alerts.test enqueues a test alert and delivers the sample payload" do
    project = create_test_project!
    org = project.organization
    org.update!(alert_webhook_url: "https://alerts.test/hook")

    captured = nil
    stub = stub_request(:post, "https://alerts.test/hook")
      .with { |req| captured = req; true }
      .to_return(status: 200)

    assert_enqueued_jobs 1, only: AlertWebhookJob do
      Alerts.test(org)
    end

    perform_enqueued_jobs only: AlertWebhookJob

    assert_requested stub
    body = JSON.parse(captured.body)
    assert_equal "test", body["type"]
    assert_equal "Test alert from Hookrail. Your receiver is wired up.", body["data"]["message"]
  end
end
