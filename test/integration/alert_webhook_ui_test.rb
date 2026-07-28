require "test_helper"

class AlertWebhookUiTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new(
      provider: "github", uid: "12345",
      info: { nickname: "octocat", name: "The Octocat", email: "octo@example.com", image: "https://avatars/1" }
    )
  end

  teardown do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:github] = nil
  end

  def sign_in!
    post "/auth/github"
    follow_redirect!
  end

  def current_organization
    User.find_by(github_uid: "12345").organization
  end

  test "show renders the url field" do
    sign_in!

    get alert_webhook_path
    assert_response :ok
    assert_match(/name="organization\[alert_webhook_url\]"/, response.body)
  end

  test "show offers an add card for every unconfigured channel" do
    sign_in!

    get alert_webhook_path
    assert_response :ok
    assert_select "button[title=?][data-action=?]", "Webhook", "dialog#open"
    assert_select "button[title=?][data-action=?]", "Slack", "dialog#open"
    assert_select "button[title=?][data-action=?]", "Discord", "dialog#open"
  end

  test "a configured channel gets a row instead of an add card" do
    sign_in!
    current_organization.update!(slack_webhook_url: "https://hooks.slack.com/services/T/B/x")

    get alert_webhook_path
    assert_response :ok
    assert_match "https://hooks.slack.com/services/T/B/x", response.body
    assert_select "button[title=?]", "Slack", count: 0
    assert_select "button[title=?][data-action=?]", "Discord", "dialog#open"
  end

  test "removing a chat channel patches its url blank" do
    sign_in!
    current_organization.update!(slack_webhook_url: "https://hooks.slack.com/services/T/B/x")

    patch alert_webhook_path, params: { organization: { slack_webhook_url: "" } }
    assert_redirected_to alert_webhook_path
    assert_nil current_organization.slack_webhook_url
  end

  test "an invalid chat url reopens that channel's dialog" do
    sign_in!

    patch alert_webhook_path, params: { organization: { discord_webhook_url: "nope" } }
    assert_response :unprocessable_entity
    assert_match "must be an http(s) URL", response.body
    assert_select "[data-controller=dialog][data-dialog-open-value=true]", count: 1
  end

  test "update with a valid url saves it and shows the generated secret" do
    sign_in!

    patch alert_webhook_path, params: { organization: { alert_webhook_url: "https://alerts.test/hook" } }
    assert_redirected_to alert_webhook_path
    follow_redirect!
    assert_match "Alert webhook saved.", response.body
    assert_match current_organization.alert_webhook_secret, response.body
  end

  test "update with an invalid url re-renders with the validation error" do
    sign_in!

    patch alert_webhook_path, params: { organization: { alert_webhook_url: "not a url" } }
    assert_response :unprocessable_entity
    assert_match "must be an http(s) URL", response.body
    assert_nil current_organization.alert_webhook_url
  end

  test "test sends a test alert when a url is configured" do
    sign_in!
    current_organization.update!(alert_webhook_url: "https://alerts.test/hook")

    assert_enqueued_jobs 1, only: AlertWebhookJob do
      post test_alert_webhook_path
    end
    assert_redirected_to alert_webhook_path
    follow_redirect!
    assert_match "Test alert sent.", response.body

    _org_id, type, = enqueued_jobs.find { |j| j[:job] == AlertWebhookJob }[:args]
    assert_equal "test", type
  end

  test "test without a configured url enqueues nothing" do
    sign_in!

    assert_no_enqueued_jobs only: AlertWebhookJob do
      post test_alert_webhook_path
    end
    assert_redirected_to alert_webhook_path
    follow_redirect!
    assert_match "Configure a URL first.", response.body
  end

  test "destroy clears the url and the secret" do
    sign_in!
    current_organization.update!(alert_webhook_url: "https://alerts.test/hook")

    delete alert_webhook_path
    assert_redirected_to alert_webhook_path
    follow_redirect!
    assert_match "Alert webhook removed.", response.body

    organization = current_organization
    assert_nil organization.alert_webhook_url
    assert_nil organization.alert_webhook_secret
  end

  test "the organization settings nav links to the alert webhook page" do
    sign_in!

    get members_path
    assert_response :ok
    assert_select "a[href=?]", alert_webhook_path
  end
end
