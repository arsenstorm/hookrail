require "test_helper"

class OrganizationsUiTest < ActionDispatch::IntegrationTest
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

  test "creating an organization switches to it with the user as owner" do
    user = make_user!("neworg1")
    sign_in_as!(user)

    assert_difference "Organization.count", 1 do
      post new_organization_path, params: { organization: { name: "Acme" } }
    end
    assert_redirected_to dashboard_path

    org = Organization.find_by!(name: "Acme")
    assert_equal user, org.owner
    assert_equal "owner", org.memberships.find_by!(user: user).role
    assert_equal [ "Default" ], org.projects.pluck(:name)

    follow_redirect!
    assert_match "Acme", response.body
  end

  test "a plain member of another org can create their own and owns it" do
    owner = make_user!("neworg2")
    member = User.create!(github_uid: "uid-neworg3", github_login: "neworg3", email: "neworg3@example.com")
    Membership.create!(organization: owner.organization, user: member, role: "member")
    sign_in_as!(member)

    post new_organization_path, params: { organization: { name: "Member Co" } }
    assert_redirected_to dashboard_path

    org = Organization.find_by!(name: "Member Co")
    assert_equal "owner", org.memberships.find_by!(user: member).role
    assert_equal 2, member.memberships.count
  end

  test "a blank name re-renders the form with an error" do
    sign_in_as!(make_user!("neworg4"))

    assert_no_difference "Organization.count" do
      post new_organization_path, params: { organization: { name: "" } }
    end
    assert_response :unprocessable_entity
    assert_match "Name can&#39;t be blank", response.body
  end

  test "signed-out users are sent to sign in" do
    get new_organization_path
    assert_redirected_to sign_in_path
  end
end
