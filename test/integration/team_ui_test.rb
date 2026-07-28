require "test_helper"

class TeamUiTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
  end

  teardown do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:github] = nil
  end

  def make_owner!(login)
    user = User.create!(github_uid: "uid-#{login}", github_login: login, email: "#{login}@example.com")
    user.ensure_org_and_project!
    user
  end

  # ponytail: no ensure_org_and_project! — the team membership stays their only
  # one, so sign-in resolves to the org under test rather than a personal org.
  def add_teammate!(organization, login, role:)
    user = User.create!(github_uid: "uid-#{login}", github_login: login, email: "#{login}@example.com")
    Membership.create!(organization: organization, user: user, role: role)
  end

  def sign_in_as!(user)
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new(
      provider: "github", uid: user.github_uid,
      info: { nickname: user.github_login, name: user.name, email: user.email, image: nil }
    )
    post "/auth/github"
    follow_redirect!
  end

  test "the members page lists the team and only admins reach it" do
    owner = make_owner!("mowner")
    member = add_teammate!(owner.organization, "mmember", role: "member").user

    sign_in_as!(owner)
    get members_path
    assert_response :ok
    assert_match owner.github_login, response.body
    assert_match member.github_login, response.body

    reset!
    sign_in_as!(member)
    get members_path
    assert_redirected_to dashboard_path
  end

  test "the invite form sits behind a dialog trigger" do
    owner = make_owner!("downer")
    sign_in_as!(owner)

    get members_path
    assert_response :ok
    assert_select "button[data-action=?]", "dialog#open", text: "Invite someone"
    assert_select "dialog form[action=?]", invitations_path
  end

  test "inviting shows a copyable link and revoking removes it" do
    owner = make_owner!("iowner")
    sign_in_as!(owner)

    assert_difference "Invitation.count", 1 do
      post invitations_path, params: { invitation: { email: "new@example.com", role: "member" } }
    end
    invitation = Invitation.last

    get members_path
    assert_response :ok
    assert_match "new@example.com", response.body
    assert_match invite_url(invitation.token), response.body

    delete invitation_path(invitation)
    assert_not Invitation.exists?(invitation.id)

    follow_redirect!
    assert_response :ok
    assert_no_match invitation.token, response.body
  end

  test "editing a member's role and grants from the page" do
    owner = make_owner!("eowner")
    project = owner.organization.projects.first
    membership = add_teammate!(owner.organization, "eadmin", role: "admin")

    sign_in_as!(owner)
    patch member_path(membership), params: {
      membership: { role: "member", grants: { project.id.to_s => "viewer" } }
    }
    assert_redirected_to members_path

    assert_equal "member", membership.reload.role
    assert_equal "viewer", membership.project_grants.find_by(project: project)&.level
  end

  test "admins cannot transfer ownership" do
    owner = make_owner!("towner")
    membership = add_teammate!(owner.organization, "tadmin", role: "admin")

    sign_in_as!(membership.user)
    post transfer_ownership_member_path(membership)
    assert_redirected_to dashboard_path

    assert_equal "admin", membership.reload.role
    assert_equal "owner", owner.organization.memberships.find_by(user: owner).role
    assert_equal owner.id, owner.organization.reload.owner_id
  end

  test "org pages swap the app sidebar for the settings sidebar" do
    user = make_owner!("sidebars")

    sign_in_as!(user)
    get members_path
    assert_response :ok
    assert_select "aside a[href=?]", dashboard_path, text: /Dashboard/
    # The Monitor group rides along on /org; the settings-only pages don't.
    assert_select "aside a[href=?]", events_path
    assert_select "aside a[href=?]", api_keys_path
    assert_select "aside a[href=?]", new_organization_path, text: /New organization/

    get dashboard_path
    assert_response :ok
    assert_select "aside a[href=?]", events_path
    assert_select "aside a[href=?]", api_keys_path, count: 0
    # Org settings is a pinned nav item now, not a switcher-menu row.
    assert_select "aside a[href=?]", members_path, text: /Organization settings/
    assert_select "aside [role=menu] a[href=?]", members_path, count: 0
  end

  test "the org switcher switches org" do
    user = make_owner!("switcher")
    other = make_owner!("otherorg")
    membership = Membership.create!(organization: other.organization, user: user, role: "member")
    ProjectGrant.create!(membership: membership, project: other.organization.projects.first, level: "viewer")

    sign_in_as!(user)
    get dashboard_path
    assert_response :ok
    assert_select "aside [role=menu] p", text: user.organization.name

    post switch_org_path(other.organization.id)
    follow_redirect!
    assert_response :ok
    assert_select "aside [role=menu] p", text: other.organization.name
  end
end
