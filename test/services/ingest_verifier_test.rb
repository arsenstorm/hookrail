require "test_helper"

# The verifier answers two questions, and both matter: is this body authentic,
# and is this delivery fresh. These cover the cases where the second one used
# to be skipped, and the case where the boundary between the two signed fields
# was attacker-movable.
class IngestVerifierTest < ActiveSupport::TestCase
  SECRET = "whsec_test"

  setup do
    @project = create_test_project!
  end

  def stripe_style_source(tolerance: nil)
    @project.sources.create!(
      name: "Stripe-ish",
      verification_secret: SECRET,
      verification_header: "Stripe-Signature",
      verification_header_format: "kv",
      verification_signature_key: "v1",
      verification_timestamp_key: "t",
      verification_payload_template: "{timestamp}.{body}",
      verification_algorithm: "sha256",
      verification_encoding: "hex",
      verification_tolerance_seconds: tolerance
    )
  end

  def sign(timestamp, body)
    OpenSSL::HMAC.hexdigest("SHA256", SECRET, "#{timestamp}.#{body}")
  end

  def request_with(header)
    ActionDispatch::TestRequest.create.tap { |r| r.headers["Stripe-Signature"] = header }
  end

  def verify(source, timestamp, signature, body)
    Ingest::Verifier.verify(
      source: source,
      request: request_with("t=#{timestamp},v1=#{signature}"),
      body: body
    )
  end

  test "a correctly signed, fresh request verifies" do
    source = stripe_style_source(tolerance: 300)
    now = Time.current.to_i
    body = '{"amount":10.50}'

    assert verify(source, now, sign(now, body), body).ok?
  end

  # The boundary attack: move a prefix of the body into the timestamp field.
  # The signed bytes are byte-identical, so the HMAC verifies — the only thing
  # standing between this and a forged (truncated) body is timestamp validation.
  test "rejects a timestamp carrying part of the body" do
    source = stripe_style_source(tolerance: 300)
    now = Time.current.to_i
    body = '{"amount":10.50}'
    split = body.index(".")
    shifted_timestamp = "#{now}.#{body[0...split]}"
    truncated_body = body[(split + 1)..]

    # Same signature as the honest request — the signed bytes are identical.
    signature = sign(now, body)
    assert_equal "#{now}.#{body}", "#{shifted_timestamp}.#{truncated_body}"

    result = verify(source, shifted_timestamp, signature, truncated_body)
    assert_not result.ok?
    assert_equal "malformed timestamp", result.reason
  end

  test "rejects a non-numeric timestamp outright" do
    source = stripe_style_source(tolerance: 300)
    result = verify(source, "not-a-number", sign("not-a-number", "{}"), "{}")

    assert_not result.ok?
    assert_equal "malformed timestamp", result.reason
  end

  # Previously a source with no configured tolerance skipped the freshness
  # check entirely, so a captured request replayed forever.
  test "applies a default tolerance when the source configured none" do
    source = stripe_style_source(tolerance: nil)
    stale = 1.hour.ago.to_i
    body = '{"ok":true}'

    result = verify(source, stale, sign(stale, body), body)
    assert_not result.ok?
    assert_equal "timestamp outside tolerance", result.reason

    fresh = Time.current.to_i
    assert verify(source, fresh, sign(fresh, body), body).ok?
  end

  test "still fails closed when a configured timestamp does not arrive" do
    source = stripe_style_source(tolerance: 300)
    request = ActionDispatch::TestRequest.create
    request.headers["Stripe-Signature"] = "v1=#{sign("", "{}")}"

    result = Ingest::Verifier.verify(source: source, request: request, body: "{}")
    assert_not result.ok?
    assert_equal "missing timestamp", result.reason
  end

  # Sources whose provider signs the body only (GitHub, Shopify) carry no
  # timestamp at all; the default must not break them.
  test "body-only verification is unaffected by the default tolerance" do
    source = @project.sources.create!(
      name: "GitHub-ish", verification_secret: SECRET,
      verification_header: "X-Hub-Signature-256",
      verification_header_format: "value",
      verification_signature_prefix: "sha256=",
      verification_payload_template: "{body}"
    )
    body = '{"ref":"refs/heads/main"}'
    request = ActionDispatch::TestRequest.create
    request.headers["X-Hub-Signature-256"] =
      "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", SECRET, body)}"

    assert Ingest::Verifier.verify(source: source, request: request, body: body).ok?
  end

  test "a body containing a placeholder is not rescanned as one" do
    source = stripe_style_source(tolerance: 300)
    now = Time.current.to_i
    body = "{timestamp}"

    assert verify(source, now, sign(now, body), body).ok?
  end
end
