require "test_helper"

class CliAuthFlowTest < ActionDispatch::IntegrationTest
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

  def auth(raw)
    { "Authorization" => "Bearer #{raw}" }
  end

  def start_device_flow!(device_name: "test device")
    post "/api/v1/cli/device_authorizations", params: { device_name: device_name }
    assert_response :created
    JSON.parse(response.body)
  end

  def poll_token(device_code)
    post "/api/v1/cli/device_authorizations/token", params: { device_code: device_code }
    response
  end

  test "happy path: start, approve with a sloppy code, poll, whoami, single issuance" do
    body = start_device_flow!(device_name: "arsen's laptop")
    assert_match(/\A[BCDFGHJKLMNPQRSTVWXZ2-9]{4}-[BCDFGHJKLMNPQRSTVWXZ2-9]{4}\z/, body["user_code"])
    device_code = body["device_code"]

    poll_token(device_code)
    assert_response :accepted
    assert_equal "pending", JSON.parse(response.body)["status"]

    owner = make_user!("owner1")
    sign_in_as!(owner)

    sloppy_code = body["user_code"].downcase.delete("-")
    post "/cli/authorize", params: { code: sloppy_code, decision: "approve" }
    assert_redirected_to dashboard_path

    poll_token(device_code)
    assert_response :ok
    token_body = JSON.parse(response.body)
    assert token_body["token"].start_with?("hkc_")
    assert_equal owner.organization.id, token_body["organization"]["id"]
    assert_equal owner.organization.name, token_body["organization"]["name"]

    get "/api/v1/cli/whoami", headers: auth(token_body["token"])
    assert_response :ok
    whoami = JSON.parse(response.body)
    assert_equal owner.github_login, whoami["user"]["github_login"]
    assert_equal "cli", whoami["token"]["kind"]

    poll_token(device_code)
    assert_response :gone
    assert_equal "authorization_gone", JSON.parse(response.body)["error"]["code"]
  end

  test "denied authorization is gone on poll" do
    body = start_device_flow!
    owner = make_user!("owner2")
    sign_in_as!(owner)

    post "/cli/authorize", params: { code: body["user_code"], decision: "deny" }
    assert_redirected_to dashboard_path

    poll_token(body["device_code"])
    assert_response :gone
    assert_equal "authorization_gone", JSON.parse(response.body)["error"]["code"]
  end

  test "expired authorization is gone on poll" do
    body = start_device_flow!

    travel CliAuthorization::TTL + 1.minute do
      poll_token(body["device_code"])
      assert_response :gone
      assert_equal "authorization_gone", JSON.parse(response.body)["error"]["code"]
    end
  end

  test "a garbage device code is gone on poll" do
    poll_token("not-a-real-device-code")
    assert_response :gone
    assert_equal "authorization_gone", JSON.parse(response.body)["error"]["code"]
  end

  test "unauthenticated browser POST to /cli/authorize redirects to login" do
    body = start_device_flow!
    post "/cli/authorize", params: { code: body["user_code"], decision: "approve" }
    assert_redirected_to sign_in_path
  end

  test "a viewer's CLI token can read but not write, an editor's token can write" do
    alice = make_user!("alice")
    alice_org = alice.organization
    alice_project = alice_org.projects.first
    source = alice_project.sources.create!(name: "GH-Source")
    destination = alice_project.destinations.create!(name: "API-Dest", url: "https://dest.test/hook")
    connection = alice_project.connections.create!(source: source, destination: destination)

    viewer = User.create!(github_uid: "uid-viewer", github_login: "viewer", email: "viewer@example.com")
    viewer_membership = Membership.create!(organization: alice_org, user: viewer, role: "member")
    ProjectGrant.create!(membership: viewer_membership, project: alice_project, level: "viewer")
    viewer_token, viewer_raw = CliToken.issue!(user: viewer, organization: alice_org, name: "viewer's box")

    editor = User.create!(github_uid: "uid-editor", github_login: "editor", email: "editor@example.com")
    editor_membership = Membership.create!(organization: alice_org, user: editor, role: "member")
    ProjectGrant.create!(membership: editor_membership, project: alice_project, level: "editor")
    _editor_token, editor_raw = CliToken.issue!(user: editor, organization: alice_org, name: "editor's box")

    event = source.events.create!(http_method: "POST", path: "/wh", received_at: Time.current, headers: {}, body: "{}")

    get "/api/v1/events", headers: auth(viewer_raw)
    assert_response :ok

    post "/api/v1/events/#{event.id}/retries", params: { connection_id: connection.id }, headers: auth(viewer_raw)
    assert_response :forbidden
    assert_equal "forbidden", JSON.parse(response.body)["error"]["code"]

    post "/api/v1/events/#{event.id}/retries", params: { connection_id: connection.id }, headers: auth(editor_raw)
    assert_response :unprocessable_entity
    assert_equal "not_retryable", JSON.parse(response.body)["error"]["code"]

    assert viewer_token.persisted?
  end

  test "removing the membership invalidates a previously working token" do
    alice = make_user!("alice")
    dave = User.create!(github_uid: "uid-dave", github_login: "dave", email: "dave@example.com")
    membership = Membership.create!(organization: alice.organization, user: dave, role: "member")
    ProjectGrant.create!(membership: membership, project: alice.organization.projects.first, level: "editor")
    _token, raw = CliToken.issue!(user: dave, organization: alice.organization, name: "dave's box")

    get "/api/v1/cli/whoami", headers: auth(raw)
    assert_response :ok

    membership.destroy!

    get "/api/v1/cli/whoami", headers: auth(raw)
    assert_response :unauthorized
  end

  test "self-revoke via DELETE /api/v1/cli/token, and rejects API keys" do
    owner = make_user!("owner3")
    _token, raw = CliToken.issue!(user: owner, organization: owner.organization, name: "owner's box")

    delete "/api/v1/cli/token", headers: auth(raw)
    assert_response :no_content

    get "/api/v1/cli/whoami", headers: auth(raw)
    assert_response :unauthorized

    _key, key_raw = ApiKey.issue!(organization: owner.organization, name: "test key")
    delete "/api/v1/cli/token", headers: auth(key_raw)
    assert_response :bad_request
    assert_equal "bad_request", JSON.parse(response.body)["error"]["code"]
  end

  test "an admin can revoke a CLI token from the dashboard; a non-admin cannot" do
    owner = make_user!("owner4")
    org = owner.organization
    member = User.create!(github_uid: "uid-member4", github_login: "member4", email: "member4@example.com")
    Membership.create!(organization: org, user: member, role: "member")
    token, raw = CliToken.issue!(user: member, organization: org, name: "member's box")

    sign_in_as!(owner)
    delete cli_token_path(token)
    assert_redirected_to api_keys_path

    get "/api/v1/cli/whoami", headers: auth(raw)
    assert_response :unauthorized

    # A member can revoke their own token, but not somebody else's.
    own_token, own_raw = CliToken.issue!(user: member, organization: org, name: "member's other box")
    owners_token, owners_raw = CliToken.issue!(user: owner, organization: org, name: "owner's box")
    reset!
    sign_in_as!(member)

    delete cli_token_path(own_token)
    assert_redirected_to security_account_path
    get "/api/v1/cli/whoami", headers: auth(own_raw)
    assert_response :unauthorized

    delete cli_token_path(owners_token)
    assert_redirected_to dashboard_path
    get "/api/v1/cli/whoami", headers: auth(owners_raw)
    assert_response :ok
  end

  test "existing hk_ API key auth still works" do
    org = make_user!("owner6").organization
    _key, raw = ApiKey.issue!(organization: org, name: "smoke test")

    get "/api/v1/sources", headers: auth(raw)
    assert_response :ok
  end
end
