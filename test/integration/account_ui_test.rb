require "test_helper"

class AccountUiTest < ActionDispatch::IntegrationTest
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
      info: { nickname: user.github_login, name: user.name, email: user.email, image: user.avatar_url }
    )
    post "/auth/github"
    follow_redirect!
  end

  def make_user!(login, **attrs)
    user = User.create!(github_uid: "uid-#{login}", github_login: login,
                        email: "#{login}@example.com", **attrs)
    user.ensure_org_and_project!
    user
  end

  test "the sidebar menu links to the account pages" do
    sign_in_as!(make_user!("menuowner", name: "Menu Owner"))

    get root_path
    assert_response :ok
    assert_select "aside details summary", text: /Menu Owner/
    assert_select "a[href=?]", account_path, text: "Account settings"
    assert_select "a[href=?]", security_account_path, text: "Security"
  end

  test "account settings shows the github profile and every org membership" do
    owner = make_user!("acctowner", name: "Acct Owner", avatar_url: "https://avatars/1")
    other = make_user!("acctother")
    Membership.create!(organization: other.organization, user: owner, role: "member")

    sign_in_as!(owner)

    get account_path
    assert_response :ok
    assert_match "Acct Owner", response.body
    assert_match "acctowner@example.com", response.body
    assert_select "img[src=?]", "https://avatars/1"
    assert_match other.organization.name, response.body
  end

  test "security lists your own cli tokens and lets a non-admin revoke one" do
    owner = make_user!("secowner")
    member = User.create!(github_uid: "uid-secmember", github_login: "secmember", email: "secmember@example.com")
    Membership.create!(organization: owner.organization, user: member, role: "member")

    mine, = CliToken.issue!(user: member, organization: owner.organization, name: "laptop")
    theirs, = CliToken.issue!(user: owner, organization: owner.organization, name: "owner-box")

    sign_in_as!(member)

    get security_account_path
    assert_response :ok
    assert_match "laptop", response.body
    assert_no_match "owner-box", response.body

    delete cli_token_path(mine)
    assert_not_nil mine.reload.revoked_at

    # ...but not somebody else's: that still needs org admin.
    delete cli_token_path(theirs)
    assert_redirected_to root_path
    assert_nil theirs.reload.revoked_at
  end
end
