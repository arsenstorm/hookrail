require "test_helper"

class ApiKeysUiTest < ActionDispatch::IntegrationTest
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

  test "index lists an issued key's name and prefix" do
    sign_in!
    key, raw = ApiKey.issue!(organization: current_organization, name: "CI deploy")

    get api_keys_path
    assert_response :ok
    assert_match "CI deploy", response.body
    assert_match key.prefix, response.body
    assert_no_match raw, response.body
  end

  test "both empty tables keep their headers and put the empty state in a row" do
    sign_in!

    get api_keys_path
    assert_response :ok
    assert_select "table thead th", text: "Key"
    assert_select "table tbody td[colspan=4]", text: /No API keys yet/
    assert_select "table thead th", text: "Last used"
    assert_select "table tbody td[colspan=5]", text: /No CLI tokens yet/
  end

  test "index opens key creation from a dialog trigger" do
    sign_in!

    get api_keys_path
    assert_response :ok
    assert_select "button[data-action=?]", "dialog#open", text: "Create key"
    assert_select "dialog form[action=?]", api_keys_path
  end

  test "create shows the raw key once and never again" do
    sign_in!

    post api_keys_path, params: { api_key: { name: "Laptop" } }
    assert_redirected_to api_keys_path
    follow_redirect!

    raw = ApiKey.order(:created_at).last.prefix
    assert_match "will not be shown again", response.body
    full_key = response.body[/hk_[0-9a-f]{48}/]
    assert full_key.present?, "expected the full raw key in the response"
    assert full_key.start_with?(raw)

    get api_keys_path
    assert_no_match full_key, response.body
  end

  test "revoke marks the key revoked" do
    sign_in!
    key, = ApiKey.issue!(organization: current_organization, name: "Old key")

    delete api_key_path(key)
    assert_redirected_to api_keys_path
    assert_not_nil key.reload.revoked_at

    follow_redirect!
    assert_match "Old key", response.body
    assert_no_match(/Revoke/, response.body)
  end

  test "another org's key 404s on revoke" do
    sign_in!
    theirs, = ApiKey.issue!(organization: create_test_project!.organization, name: "Theirs")

    delete api_key_path(theirs)
    assert_response :not_found
    assert_nil theirs.reload.revoked_at
  end

  test "unauthenticated requests redirect to login" do
    get api_keys_path
    assert_redirected_to sign_in_path
  end
end
