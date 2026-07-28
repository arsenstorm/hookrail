require "test_helper"

class IssuesUiTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    OmniAuth.config.test_mode = true
  end

  teardown do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:github] = nil
  end

  def sign_in_as!(user)
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new(
      provider: "github", uid: user.github_uid,
      info: { nickname: user.github_login, name: user.name, email: user.email, image: nil }
    )
    post "/auth/github"
    follow_redirect!
  end

  def make_user!(login)
    user = User.create!(github_uid: "uid-#{login}", github_login: login, email: "#{login}@example.com")
    user.ensure_org_and_project!
    user
  end

  def build_connection!(project, source, destination)
    project.connections.create!(source: source, destination: destination)
  end

  test "an empty index keeps the table header and puts the empty state in a row" do
    owner = make_user!("issueempty")
    sign_in_as!(owner)

    get issues_path
    assert_response :ok
    assert_select "table thead th", text: "Subject"
    assert_select "table tbody td[colspan=6]", text: /No open issues/
    assert_select "table tbody a", text: "View unresolved", count: 0

    # Filtering to a state that happens to be empty is its own message, plus a
    # way back to the default view.
    get issues_path(status: "resolved")
    assert_response :ok
    assert_select "table tbody td[colspan=6]", text: /No resolved issues/
    assert_select "table tbody a[href=?]", issues_path, text: "View unresolved"
  end

  test "index defaults to unresolved newest first, and status filters partition correctly" do
    owner = make_user!("issueowner1")
    project = owner.organization.projects.first
    source = project.sources.create!(name: "S1")
    destination = project.destinations.create!(name: "D1", url: "https://dest.test/hook")
    connection = build_connection!(project, source, destination)

    Issue.record!(type: "webhook_quarantined", subject: source, summary: "bad sig")
    travel 1.minute
    Issue.record!(type: "delivery_failure", subject: connection, summary: "5xx")
    Issue.auto_resolve!(type: "webhook_quarantined", subject: source)

    sign_in_as!(owner)

    get issues_path
    assert_response :ok
    assert_match "Delivery failure", response.body
    assert_no_match "Webhook quarantined", response.body

    get issues_path(status: "resolved")
    assert_response :ok
    assert_match "Webhook quarantined", response.body
    assert_no_match "Delivery failure", response.body

    # No pill links here anymore, but old bookmarks still filter.
    get issues_path(status: "open")
    assert_response :ok
    assert_match "Delivery failure", response.body
    assert_no_match "Webhook quarantined", response.body

    get issues_path(status: "all")
    assert_response :ok
    assert_match "Delivery failure", response.body
    assert_match "Webhook quarantined", response.body
    assert_operator response.body.index("Delivery failure"), :<, response.body.index("Webhook quarantined")
  end

  test "owner can acknowledge an open issue and then resolve it" do
    owner = make_user!("issueowner2")
    project = owner.organization.projects.first
    source = project.sources.create!(name: "S2")

    Issue.record!(type: "webhook_quarantined", subject: source, summary: "bad sig")
    issue = Issue.find_by(subject: source, issue_type: "webhook_quarantined")

    sign_in_as!(owner)

    patch acknowledge_issue_path(issue)
    assert_redirected_to issues_path
    follow_redirect!
    assert_match "Issue acknowledged.", response.body
    assert issue.reload.status_acknowledged?

    patch resolve_issue_path(issue)
    assert_redirected_to issues_path
    follow_redirect!
    assert_match "Issue resolved.", response.body
    assert issue.reload.status_resolved?
  end

  test "acknowledging a non-open issue redirects with an alert and does not change status" do
    owner = make_user!("issueowner3")
    project = owner.organization.projects.first
    source = project.sources.create!(name: "S3")

    Issue.record!(type: "webhook_quarantined", subject: source, summary: "bad sig")
    issue = Issue.find_by(subject: source, issue_type: "webhook_quarantined")
    issue.update!(status: :resolved)

    sign_in_as!(owner)

    patch acknowledge_issue_path(issue)
    assert_redirected_to issues_path
    follow_redirect!
    assert_match "Only open issues can be acknowledged.", response.body
    assert issue.reload.status_resolved?
  end

  test "a member with a viewer grant can see issues but cannot acknowledge one" do
    alice = make_user!("issuealice")
    alice_org = alice.organization
    alice_project = alice_org.projects.first
    source = alice_project.sources.create!(name: "S4")

    Issue.record!(type: "webhook_quarantined", subject: source, summary: "bad sig")
    issue = Issue.find_by(subject: source, issue_type: "webhook_quarantined")

    viewer = User.create!(github_uid: "uid-issueviewer", github_login: "issueviewer", email: "issueviewer@example.com")
    viewer_membership = Membership.create!(organization: alice_org, user: viewer, role: "member")
    ProjectGrant.create!(membership: viewer_membership, project: alice_project, level: "viewer")

    sign_in_as!(viewer)

    get issues_path
    assert_response :ok

    patch acknowledge_issue_path(issue)
    assert_redirected_to dashboard_path
    follow_redirect!
    assert_match "You don&#39;t have permission to do that.", response.body
    assert issue.reload.status_open?
  end

  test "settings: chat webhook urls save, invalid urls re-render, and test alert enqueues a chat job" do
    owner = make_user!("issueowner4")

    sign_in_as!(owner)

    patch alert_webhook_path, params: { organization: {
      slack_webhook_url: "https://hooks.slack.com/services/x",
      discord_webhook_url: "https://discord.com/api/webhooks/x"
    } }
    assert_redirected_to alert_webhook_path
    assert_equal "https://hooks.slack.com/services/x", owner.organization.reload.slack_webhook_url
    assert_equal "https://discord.com/api/webhooks/x", owner.organization.reload.discord_webhook_url

    patch alert_webhook_path, params: { organization: { slack_webhook_url: "not-a-url" } }
    assert_response :unprocessable_entity

    owner.organization.update_columns(slack_webhook_url: "https://hooks.slack.com/services/x", discord_webhook_url: nil)

    assert_enqueued_jobs 1, only: ChatAlertJob do
      post test_alert_webhook_path
    end
    assert_redirected_to alert_webhook_path
    follow_redirect!
    assert_match "Test alert sent.", response.body
  end

  test "dashboard shows the issues link for a signed-in owner" do
    owner = make_user!("issueowner5")

    sign_in_as!(owner)

    get dashboard_path
    assert_response :ok
    assert_select "a[href=?]", issues_path, text: "Issues"
  end
end
