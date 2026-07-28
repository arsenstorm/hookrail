require "test_helper"

class SourceTest < ActiveSupport::TestCase
  test "invalid when secret is present but header is blank" do
    source = Source.new(name: "Test", project: create_test_project!, verification: { secret: "x" })
    assert_not source.valid?
    assert_includes source.errors[:verification_header], "can't be blank"
  end

  test "invalid when secret is present and algorithm is unsupported" do
    source = Source.new(name: "Test", project: create_test_project!, verification: { secret: "x", header: "H", algorithm: "md5" })
    assert_not source.valid?
    assert_includes source.errors[:verification_algorithm], "is not included in the list"
  end

  test "blank-string verification values are compacted on validation" do
    source = Source.new(name: "Test", project: create_test_project!, verification: { secret: "x", header: "H", algorithm: "" })
    source.valid?
    assert_not_includes source.verification.keys, "algorithm"
  end

  test "verification_enabled? is false when verification is empty" do
    source = Source.new(name: "Test", project: create_test_project!, verification: {})
    assert_not source.verification_enabled?
  end

  test "stripe preset fills in the generic verification fields" do
    source = Source.create!(name: "Test", project: create_test_project!, verification: { provider: "stripe", secret: "whsec_x" })
    assert_equal "Stripe-Signature", source.verification_header
    assert_equal "kv", source.verification_header_format
    assert_equal "v1", source.verification_signature_key
    assert_equal "t", source.verification_timestamp_key
    assert_equal "{timestamp}.{body}", source.verification_payload_template
    assert_equal "sha256", source.verification_algorithm
    assert_equal "hex", source.verification_encoding
    assert_equal 300, source.verification_tolerance_seconds
    assert source.verification_enabled?
  end

  test "preset overwrites a hand-edited field on save" do
    source = Source.create!(name: "Test", project: create_test_project!, verification: { provider: "stripe", secret: "whsec_x" })
    source.verification_header = "X-Other"
    source.save!
    assert_equal "Stripe-Signature", source.verification_header
  end

  test "unknown provider is invalid" do
    source = Source.new(name: "Test", project: create_test_project!, verification: { provider: "acme", secret: "x" })
    assert_not source.valid?
    assert_includes source.errors[:verification_provider], "is not included in the list"
  end

  test "github preset fills in the generic verification fields" do
    source = Source.create!(name: "Test", project: create_test_project!, verification: { provider: "github", secret: "ghs_x" })
    assert_equal "X-Hub-Signature-256", source.verification_header
    assert_equal "value", source.verification_header_format
    assert_equal "sha256=", source.verification_signature_prefix
    assert_equal "{body}", source.verification_payload_template
    assert_equal "sha256", source.verification_algorithm
    assert_equal "hex", source.verification_encoding
    assert_nil source.verification_tolerance_seconds
  end

  test "shopify preset fills in the generic verification fields" do
    source = Source.create!(name: "Test", project: create_test_project!, verification: { provider: "shopify", secret: "shpss_x" })
    assert_equal "X-Shopify-Hmac-Sha256", source.verification_header
    assert_equal "value", source.verification_header_format
    assert_equal "{body}", source.verification_payload_template
    assert_equal "sha256", source.verification_algorithm
    assert_equal "base64", source.verification_encoding
    assert_nil source.verification_signature_prefix
  end

  test "slack preset fills in the generic verification fields" do
    source = Source.create!(name: "Test", project: create_test_project!, verification: { provider: "slack", secret: "slack_x" })
    assert_equal "X-Slack-Signature", source.verification_header
    assert_equal "value", source.verification_header_format
    assert_equal "v0=", source.verification_signature_prefix
    assert_equal "X-Slack-Request-Timestamp", source.verification_timestamp_header
    assert_equal "v0:{timestamp}:{body}", source.verification_payload_template
    assert_equal "sha256", source.verification_algorithm
    assert_equal "hex", source.verification_encoding
    assert_equal 300, source.verification_tolerance_seconds
  end

  test "switching provider clears the previous preset's fields" do
    source = Source.create!(name: "Test", project: create_test_project!, verification: { provider: "stripe", secret: "whsec_x" })
    source.verification_provider = "github"
    source.save!
    assert_nil source.verification_tolerance_seconds
    assert_nil source.verification_timestamp_key
    assert_nil source.verification_signature_key
    assert_equal "whsec_x", source.verification_secret
  end

  test "clearing the provider keeps the previously written generic fields" do
    source = Source.create!(name: "Test", project: create_test_project!, verification: { provider: "stripe", secret: "whsec_x" })
    source.verification_provider = ""
    source.save!
    assert_equal "Stripe-Signature", source.verification_header
    assert_not_includes source.verification.keys, "provider"
  end

  test "stripe provider with no secret is valid and verification is disabled" do
    source = Source.new(name: "Test", project: create_test_project!, verification: { provider: "stripe" })
    assert source.valid?
    assert_not source.verification_enabled?
  end
end
