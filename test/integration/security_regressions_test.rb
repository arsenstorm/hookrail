require "test_helper"

# One test per vulnerability fixed in the July 2026 security review. Each fails
# against the code as it was, so a regression is visible rather than silent.
class SecurityRegressionsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def auth(raw) = { "Authorization" => "Bearer #{raw}" }

  # A plain member holding an editor grant on one project — the lowest role
  # that can do anything at all.
  def project_member!(organization, project, level: "editor")
    user = User.create!(github_uid: "member-#{SecureRandom.hex(4)}", github_login: "member")
    membership = organization.memberships.create!(user: user, role: "member")
    membership.project_grants.create!(project: project, level: level)
    _token, raw = CliToken.issue!(user: user, organization: organization, name: "cli")
    raw
  end

  # --- org-wide settings need an org-wide role -------------------------------

  test "a project editor cannot change org-wide retention through the API" do
    owner = User.create!(github_uid: "owner-#{SecureRandom.hex(4)}", github_login: "owner")
    owner.ensure_org_and_project!
    org = owner.organization
    project = org.projects.first
    org.update!(retention_days: 90)

    raw = project_member!(org, project)

    put "/api/v1/retention?project_id=#{project.id}",
        params: { retention: { days: 7 } }.to_json,
        headers: auth(raw).merge("CONTENT_TYPE" => "application/json")

    assert_response :forbidden
    assert_equal 90, org.reload.retention_days, "retention must be unchanged"
  end

  test "a project viewer cannot read the org alert webhook secret through the API" do
    owner = User.create!(github_uid: "owner-#{SecureRandom.hex(4)}", github_login: "owner")
    owner.ensure_org_and_project!
    org = owner.organization
    org.update!(alert_webhook_url: "https://alerts.example/hook")
    project = org.projects.first

    raw = project_member!(org, project, level: "viewer")

    get "/api/v1/alert_webhook?project_id=#{project.id}", headers: auth(raw)

    assert_response :forbidden
    assert_no_match org.reload.alert_webhook_secret, response.body
  end

  test "an org admin can still manage org-wide settings" do
    owner = User.create!(github_uid: "owner-#{SecureRandom.hex(4)}", github_login: "owner")
    owner.ensure_org_and_project!
    org = owner.organization
    project = org.projects.first
    _token, raw = CliToken.issue!(user: owner, organization: org, name: "cli")

    put "/api/v1/retention?project_id=#{project.id}",
        params: { retention: { days: 7 } }.to_json,
        headers: auth(raw).merge("CONTENT_TYPE" => "application/json")

    assert_response :success
    assert_equal 7, org.reload.retention_days
  end

  # --- quarantine alerting is deduped ---------------------------------------

  test "a flood of rejected webhooks sends one alert, not one per request" do
    # Alerts only go to admins who have an email address on file.
    owner = User.create!(github_uid: "owner-#{SecureRandom.hex(4)}", github_login: "owner",
                         email: "owner@example.com")
    owner.ensure_org_and_project!
    source = owner.organization.projects.first.sources.create!(
      name: "Signed", verification_secret: "s3cret", verification_header: "X-Sig"
    )

    assert_emails 1 do
      perform_enqueued_jobs only: ->(job) { job.is_a?(ActionMailer::MailDeliveryJob) } do
        5.times do
          post "/ingest/#{source.token}", params: "{}", headers: { "CONTENT_TYPE" => "application/json" }
          assert_response :unauthorized
        end
      end
    end

    assert_equal 5, source.quarantined_webhooks.count, "every rejection is still recorded"
  end

  # --- session cookies are revocable ----------------------------------------

  test "signing out invalidates a session cookie that was copied elsewhere" do
    user = User.create!(github_uid: "uid-copy", github_login: "copycat")
    user.ensure_org_and_project!
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new(
      provider: "github", uid: "uid-copy",
      info: { nickname: "copycat", name: "Copy Cat", email: "copy@example.com", image: nil }
    )
    post "/auth/github"
    follow_redirect!

    stolen = cookies["_hookrail_session"]
    get "/app"
    assert_response :success

    delete sign_out_path

    # A different browser replaying the captured cookie must not be signed in.
    reset!
    cookies["_hookrail_session"] = stolen
    get "/app"
    assert_redirected_to sign_in_path
  ensure
    OmniAuth.config.test_mode = false
  end

  # --- ingest limits ---------------------------------------------------------

  test "an oversized body is refused before it is buffered" do
    owner = User.create!(github_uid: "owner-#{SecureRandom.hex(4)}", github_login: "owner")
    owner.ensure_org_and_project!
    source = owner.organization.projects.first.sources.create!(name: "Big")

    post "/ingest/#{source.token}", params: "{}",
         headers: { "CONTENT_TYPE" => "application/json",
                    "CONTENT_LENGTH" => (IngestController::MAX_BODY_BYTES + 1).to_s }

    assert_response :payload_too_large
    assert_equal 0, source.events.count
  end

  test "inbound credentials are neither stored nor forwarded" do
    owner = User.create!(github_uid: "owner-#{SecureRandom.hex(4)}", github_login: "owner")
    owner.ensure_org_and_project!
    source = owner.organization.projects.first.sources.create!(name: "Auth")

    post "/ingest/#{source.token}", params: '{"ok":true}',
         headers: { "CONTENT_TYPE" => "application/json",
                    "HTTP_AUTHORIZATION" => "Bearer sender-secret-token" }
    assert_response :ok

    stored = source.events.last.headers
    assert_not_includes stored.values.join(" "), "sender-secret-token"
    assert_includes Delivery::Client::SKIP_FORWARD_HEADERS, "authorization"
  end

  # --- content security policy ----------------------------------------------

  test "pages ship a script-src policy with a nonce and no unsafe-inline" do
    user = User.create!(github_uid: "uid-csp", github_login: "csp")
    user.ensure_org_and_project!
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new(
      provider: "github", uid: "uid-csp",
      info: { nickname: "csp", name: "CSP", email: "csp@example.com", image: nil }
    )
    post "/auth/github"
    follow_redirect!

    get "/app"
    assert_response :success
    policy = response.headers["Content-Security-Policy"].to_s
    assert_match(/script-src 'self' 'nonce-/, policy)
    assert_no_match(/script-src[^;]*unsafe-inline/, policy)
    assert_match(/object-src 'none'/, policy)
    # OAuth kickoff redirects to github.com; form-action is checked on redirects.
    assert_match(%r{form-action 'self' https://github\.com}, policy)
    # Every inline script must carry the nonce, or the page is broken under it.
    inline_scripts = response.body.scan(/<script(?![^>]*\ssrc=)[^>]*>/)
    assert inline_scripts.any?, "expected at least one inline script to check"
    inline_scripts.each { |tag| assert_match(/nonce=/, tag, "inline script without a nonce: #{tag}") }
  ensure
    OmniAuth.config.test_mode = false
  end
end
