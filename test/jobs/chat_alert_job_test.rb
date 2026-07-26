require "test_helper"

class ChatAlertJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def build_connection!(project, url: "https://dest-#{SecureRandom.hex(3)}.test/hook")
    source      = Source.create!(project: project, name: "S-#{SecureRandom.hex(3)}")
    destination = Destination.create!(project: project, name: "D-#{SecureRandom.hex(3)}", url: url)
    Connection.create!(project: project, source: source, destination: destination)
  end

  test "posts to slack with the exact text body" do
    project = create_test_project!
    org = project.organization
    org.update!(slack_webhook_url: "https://hooks.slack.test/T/B/x")

    stub = stub_request(:post, org.slack_webhook_url)
      .with(body: '{"text":"hello"}').to_return(status: 200)

    ChatAlertJob.perform_now(org.id, "slack", "hello")

    assert_requested stub
  end

  test "posts to discord with the exact content body" do
    project = create_test_project!
    org = project.organization
    org.update!(discord_webhook_url: "https://discord.test/api/webhooks/1/x")

    stub = stub_request(:post, org.discord_webhook_url)
      .with(body: '{"content":"hello"}').to_return(status: 200)

    ChatAlertJob.perform_now(org.id, "discord", "hello")

    assert_requested stub
  end

  test "a non-2xx response raises ChatDeliveryError" do
    project = create_test_project!
    org = project.organization
    org.update!(slack_webhook_url: "https://hooks.slack.test/T/B/x")

    stub_request(:post, org.slack_webhook_url).to_return(status: 500)

    # perform (not perform_now) so retry_on's rescue_from doesn't swallow the
    # error before it reaches this assertion — retry_on catching it and
    # rescheduling, silently, is exactly the intended behavior in production.
    assert_raises(ChatAlertJob::ChatDeliveryError) do
      ChatAlertJob.new.perform(org.id, "slack", "hello")
    end
  end

  test "a blank url for the requested channel makes no request and raises nothing" do
    project = create_test_project!
    org = project.organization
    org.update!(slack_webhook_url: "https://hooks.slack.test/T/B/x")

    stub = stub_request(:post, "https://discord.test/api/webhooks/1/x")

    ChatAlertJob.perform_now(org.id, "discord", "hello")

    assert_not_requested stub
  end

  test "Issue.record! enqueues one ChatAlertJob per configured channel, and each delivers the issue text" do
    project = create_test_project!
    org = project.organization
    org.update!(slack_webhook_url: "https://hooks.slack.test/T/B/x",
                discord_webhook_url: "https://discord.test/api/webhooks/1/x")
    connection = build_connection!(project)

    slack_captured = nil
    discord_captured = nil
    slack_stub = stub_request(:post, org.slack_webhook_url)
      .with { |req| slack_captured = req; true }.to_return(status: 200)
    discord_stub = stub_request(:post, org.discord_webhook_url)
      .with { |req| discord_captured = req; true }.to_return(status: 200)

    assert_enqueued_jobs 2, only: ChatAlertJob do
      Issue.record!(type: :delivery_failure, subject: connection, summary: "5 consecutive delivery failures")
    end

    perform_enqueued_jobs only: ChatAlertJob

    assert_requested slack_stub
    assert_requested discord_stub

    slack_text = JSON.parse(slack_captured.body)["text"]
    discord_text = JSON.parse(discord_captured.body)["content"]
    [ slack_text, discord_text ].each do |text|
      assert_includes text, "New issue: Delivery failure"
      assert_includes text, project.name
      assert_includes text, "http://example.com/app/issues/"
    end
  end
end
