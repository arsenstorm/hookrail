require "test_helper"

class QuarantineUiTest < ActionDispatch::IntegrationTest
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

  def current_project
    User.find_by(github_uid: "12345").organization.projects.first
  end

  def quarantine!(source, **attrs)
    source.quarantined_webhooks.create!(
      { http_method: "POST", headers: {}, reason: "signature mismatch", received_at: Time.current }.merge(attrs)
    )
  end

  test "index lists quarantined webhooks" do
    sign_in!
    source = current_project.sources.create!(name: "GH")
    quarantine!(source)

    get quarantined_webhooks_path
    assert_response :ok
    assert_match "GH", response.body
    assert_match "signature mismatch", response.body
  end

  test "index shows an empty state when nothing is quarantined" do
    sign_in!
    get quarantined_webhooks_path
    assert_response :ok
    assert_match "No quarantined webhooks", response.body
  end

  test "show renders the reason and body" do
    sign_in!
    source = current_project.sources.create!(name: "GH")
    webhook = quarantine!(source, path: "/wh", body: '{"hello":"world"}')

    get quarantined_webhook_path(webhook)
    assert_response :ok
    assert_match "signature mismatch", response.body
    assert_match "hello", response.body
  end

  test "another project's quarantined webhook is invisible and 404s" do
    sign_in!
    other = create_test_project!.sources.create!(name: "Theirs")
    theirs = quarantine!(other, reason: "their reason")

    get quarantined_webhooks_path
    assert_no_match "their reason", response.body

    get quarantined_webhook_path(theirs)
    assert_response :not_found
  end

  test "verification settings persist through the source form" do
    sign_in!
    source = current_project.sources.create!(name: "GH")

    patch source_path(source), params: { source: {
      name: "GH",
      verification_secret: "s3cr3t",
      verification_header: "X-Hub-Signature-256",
      verification_algorithm: "sha256",
      verification_encoding: "hex",
      verification_header_format: "value",
      verification_signature_prefix: "sha256=",
      verification_payload_template: "{body}"
    } }
    assert_redirected_to source_path(source)

    source.reload
    assert source.verification_enabled?
    assert_equal "X-Hub-Signature-256", source.verification_header
    assert_equal "sha256=", source.verification_signature_prefix

    get source_path(source)
    assert_match "X-Hub-Signature-256", response.body
  end

  test "unauthenticated requests redirect to login" do
    get quarantined_webhooks_path
    assert_redirected_to login_path
  end
end
