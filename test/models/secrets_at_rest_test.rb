require "test_helper"

# `encrypts` fails open when it is misconfigured: with support_unencrypted_data
# on, reads still work and nothing looks wrong. These assert against the raw
# column, which is the only place the difference shows.
class SecretsAtRestTest < ActiveSupport::TestCase
  def raw_column(model, column)
    model.class.connection.select_value(
      "SELECT #{column}::text FROM #{model.class.table_name} WHERE id = #{model.id}"
    ).to_s
  end

  def assert_encrypted(model, column, plaintext)
    raw = raw_column(model, column)
    refute_includes raw, plaintext, "#{model.class}##{column} is readable in the database"
    assert_includes raw, "\"p\"", "#{model.class}##{column} is not a Rails encrypted payload"
  end

  test "destination signing secret is encrypted at rest" do
    destination = create_test_project!.destinations.create!(
      name: "Encrypted", kind: "http", url: "https://hooks.example/x"
    )
    assert_encrypted destination, "signing_secret", destination.signing_secret
    assert_equal destination.signing_secret, destination.reload.signing_secret
  end

  test "destination auth credentials are encrypted at rest" do
    destination = create_test_project!.destinations.create!(
      name: "Bearer", kind: "http", url: "https://hooks.example/x",
      auth: { "type" => "bearer", "token" => "super-secret-token" }
    )
    assert_encrypted destination, "auth", "super-secret-token"
    assert_equal "Bearer super-secret-token", destination.reload.authorization_header
  end

  test "source verification secret is encrypted at rest" do
    source = create_test_project!.sources.create!(
      name: "Signed", verification_secret: "shhh-signing-key",
      verification_header: "X-Signature"
    )
    assert_encrypted source, "verification", "shhh-signing-key"
    assert_equal "shhh-signing-key", source.reload.verification_secret
  end

  test "organization alert webhook secret is encrypted at rest" do
    organization = create_test_project!.organization
    organization.update!(alert_webhook_url: "https://alerts.example/hook")
    assert_encrypted organization, "alert_webhook_secret", organization.alert_webhook_secret
    assert_equal organization.alert_webhook_secret, organization.reload.alert_webhook_secret
  end
end
