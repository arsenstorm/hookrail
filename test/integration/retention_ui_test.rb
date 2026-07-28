require "test_helper"

class RetentionUiTest < ActionDispatch::IntegrationTest
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
    User.find_by(github_uid: "12345").organization.reload
  end

  test "the organization settings nav links to the retention page" do
    sign_in!

    get members_path
    assert_response :ok
    assert_select "a[href=?]", retention_path
  end

  test "the page shows the current window selected" do
    sign_in!

    get retention_path
    assert_response :ok
    assert_select "input[type=radio][name='organization[retention_days]']", count: 3
    assert_select "input[type=radio][value='30'][checked]"
    # The selected state is CSS-only (has-checked:), so the radio has to stay in the DOM.
    assert_select "label.has-checked\\:bg-neutral-950\\/\\[0\\.03\\]", count: 3
  end

  test "saving a new window persists it" do
    sign_in!

    patch retention_path, params: { organization: { retention_days: "90" } }
    assert_response :redirect
    follow_redirect!
    assert_select "input[type=radio][value='90'][checked]"
    assert_equal 90, current_organization.retention_days
  end

  test "an invalid value re-renders with the error" do
    sign_in!

    patch retention_path, params: { organization: { retention_days: "14" } }
    assert_response :unprocessable_entity
    assert_match "must be 7, 30, or 90 days", response.body
    assert_equal 30, current_organization.retention_days
  end
end
