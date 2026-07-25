require "test_helper"

class IngestVerificationTest < ActionDispatch::IntegrationTest
  test "github-style valid signature is accepted" do
    source = github_source
    body = '{"hello":"world"}'
    sig = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", "testsecret", body)

    assert_difference -> { source.events.count }, 1 do
      post "/ingest/#{source.token}", params: body, headers: {
        "Content-Type" => "application/json",
        "X-Hub-Signature-256" => sig
      }
    end

    assert_response :ok
    assert_equal 0, source.quarantined_webhooks.count
  end

  test "github-style wrong signature is quarantined" do
    source = github_source
    body = '{"hello":"world"}'

    assert_no_difference -> { source.events.count } do
      assert_difference -> { source.quarantined_webhooks.count }, 1 do
        post "/ingest/#{source.token}", params: body, headers: {
          "Content-Type" => "application/json",
          "X-Hub-Signature-256" => "sha256=deadbeef"
        }
      end
    end

    assert_response :unauthorized
    webhook = source.quarantined_webhooks.last
    assert_equal "signature mismatch", webhook.reason
    assert_equal body, webhook.body
    assert_equal "sha256=deadbeef", webhook.headers["X-Hub-Signature-256"]
  end

  test "github-style missing header is quarantined" do
    source = github_source
    body = '{"hello":"world"}'

    assert_no_difference -> { source.events.count } do
      assert_difference -> { source.quarantined_webhooks.count }, 1 do
        post "/ingest/#{source.token}", params: body, headers: { "Content-Type" => "application/json" }
      end
    end

    assert_response :unauthorized
    webhook = source.quarantined_webhooks.last
    assert webhook.reason.start_with?("missing"), "expected reason to start with 'missing', got #{webhook.reason.inspect}"
  end

  test "stripe-style valid signature within tolerance is accepted" do
    source = stripe_source
    body = '{"hello":"world"}'
    ts = Time.current.to_i
    sig = OpenSSL::HMAC.hexdigest("SHA256", "whsec_test", "#{ts}.#{body}")

    assert_difference -> { source.events.count }, 1 do
      post "/ingest/#{source.token}", params: body, headers: {
        "Content-Type" => "application/json",
        "Stripe-Signature" => "t=#{ts},v1=#{sig}"
      }
    end

    assert_response :ok
  end

  test "stripe-style signature outside tolerance is quarantined" do
    source = stripe_source
    body = '{"hello":"world"}'
    ts = Time.current.to_i - 400
    sig = OpenSSL::HMAC.hexdigest("SHA256", "whsec_test", "#{ts}.#{body}")

    assert_no_difference -> { source.events.count } do
      assert_difference -> { source.quarantined_webhooks.count }, 1 do
        post "/ingest/#{source.token}", params: body, headers: {
          "Content-Type" => "application/json",
          "Stripe-Signature" => "t=#{ts},v1=#{sig}"
        }
      end
    end

    assert_response :unauthorized
    assert_equal "timestamp outside tolerance", source.quarantined_webhooks.last.reason
  end

  test "stripe-style signature accepts multiple v1 values when second matches" do
    source = stripe_source
    body = '{"hello":"world"}'
    ts = Time.current.to_i
    sig = OpenSSL::HMAC.hexdigest("SHA256", "whsec_test", "#{ts}.#{body}")

    assert_difference -> { source.events.count }, 1 do
      post "/ingest/#{source.token}", params: body, headers: {
        "Content-Type" => "application/json",
        "Stripe-Signature" => "t=#{ts},v1=bogus,v1=#{sig}"
      }
    end

    assert_response :ok
  end

  test "base64-encoded signature is accepted" do
    source = Source.create!(
      name: "Base64 Source",
      project: create_test_project!,
      verification: { secret: "testsecret", header: "X-Signature", algorithm: "sha256", encoding: "base64" }
    )
    body = '{"hello":"world"}'
    sig = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", "testsecret", body))

    assert_difference -> { source.events.count }, 1 do
      post "/ingest/#{source.token}", params: body, headers: {
        "Content-Type" => "application/json",
        "X-Signature" => sig
      }
    end

    assert_response :ok
  end

  test "source with no verification config accepts requests unchanged" do
    source = Source.create!(name: "Unverified Source", project: create_test_project!)
    body = '{"hello":"world"}'

    assert_difference -> { source.events.count }, 1 do
      post "/ingest/#{source.token}", params: body, headers: { "Content-Type" => "application/json" }
    end

    assert_response :ok
  end

  private

  def github_source
    Source.create!(
      name: "GitHub Source",
      project: create_test_project!,
      verification: {
        secret: "testsecret",
        header: "X-Hub-Signature-256",
        header_format: "value",
        signature_prefix: "sha256="
      }
    )
  end

  def stripe_source
    Source.create!(
      name: "Stripe Source",
      project: create_test_project!,
      verification: {
        secret: "whsec_test",
        header: "Stripe-Signature",
        header_format: "kv",
        signature_key: "v1",
        timestamp_key: "t",
        payload_template: "{timestamp}.{body}",
        tolerance_seconds: "300"
      }
    )
  end
end
