require "test_helper"

class AlertMailerTest < ActionMailer::TestCase
  setup do
    @project = create_test_project!
    @project.organization.owner.update!(email: "owner@example.com")
    @source = @project.sources.create!(name: "GH")
    @destination = @project.destinations.create!(name: "API", url: "https://api.test/hook")
    @connection = @project.connections.create!(source: @source, destination: @destination)
  end

  test "connection_unhealthy" do
    @connection.update!(unhealthy_since: 2.hours.ago, consecutive_failures: 5)
    mail = AlertMailer.connection_unhealthy(@connection)

    assert_equal [ "owner@example.com" ], mail.to
    assert_equal "[Hookrail] Delivery failing: GH → API", mail.subject
    assert_match "GH → API", mail.body.to_s
  end

  test "connection_recovered" do
    mail = AlertMailer.connection_recovered(@connection)

    assert_equal [ "owner@example.com" ], mail.to
    assert_equal "[Hookrail] Delivery recovered: GH → API", mail.subject
    assert_match "GH → API", mail.body.to_s
  end

  test "webhook_quarantined" do
    quarantined = @source.quarantined_webhooks.create!(
      http_method: "POST", headers: {}, reason: "signature mismatch", received_at: Time.current
    )
    mail = AlertMailer.webhook_quarantined(quarantined)

    assert_equal [ "owner@example.com" ], mail.to
    assert_equal "[Hookrail] Webhook quarantined: GH", mail.subject
    assert_match "GH", mail.body.to_s
    assert_match "signature mismatch", mail.body.to_s
  end
end
