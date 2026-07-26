require "test_helper"

class ProjectsUiTest < ActionDispatch::IntegrationTest
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

  test "owner creates a project and cannot duplicate a name case-insensitively" do
    owner = make_user!("owner1")
    sign_in_as!(owner)

    assert_difference "Project.count", 1 do
      post projects_path, params: { project: { name: "Staging" } }
    end
    assert_redirected_to projects_path
    follow_redirect!
    assert_match "Staging", response.body

    assert_no_difference "Project.count" do
      post projects_path, params: { project: { name: "staging" } }
    end
    assert_redirected_to projects_path
    follow_redirect!
    assert_match "Name has already been taken", response.body
  end

  test "renaming a project, blocked by a duplicate name" do
    owner = make_user!("owner2")
    org = owner.organization
    default_project = org.projects.first
    org.projects.create!(name: "Staging")
    sign_in_as!(owner)

    patch project_path(default_project), params: { project: { name: "Production" } }
    assert_redirected_to projects_path
    follow_redirect!
    assert_match "Production", response.body
    assert_equal "Production", default_project.reload.name

    patch project_path(default_project), params: { project: { name: "staging" } }
    assert_redirected_to projects_path
    follow_redirect!
    assert_match "Name has already been taken", response.body
    assert_equal "Production", default_project.reload.name
  end

  test "deleting the last project is blocked, deleting a second succeeds" do
    owner = make_user!("owner3")
    org = owner.organization
    project = org.projects.first
    sign_in_as!(owner)

    delete project_path(project)
    assert_redirected_to projects_path
    follow_redirect!
    assert_match "The last project in an organization can", response.body
    assert Project.exists?(project.id)

    second = org.projects.create!(name: "Staging")
    delete project_path(second)
    assert_redirected_to projects_path
    assert_not Project.exists?(second.id)
  end

  test "switching projects scopes the sources page to the new project" do
    owner = make_user!("owner4")
    org = owner.organization
    project_a = org.projects.first
    project_b = org.projects.create!(name: "B")
    project_a.sources.create!(name: "SourceA")
    project_b.sources.create!(name: "SourceB")
    membership = org.memberships.find_by(user: owner)
    sign_in_as!(owner)

    post switch_project_path(project_b.id)
    assert_redirected_to dashboard_path
    assert_equal project_b.id, membership.reload.current_project_id

    get sources_path
    assert_response :ok
    assert_match "SourceB", response.body
    assert_no_match "SourceA", response.body
  end

  test "falls back to the remaining project when the current one is deleted" do
    owner = make_user!("owner5")
    org = owner.organization
    project_a = org.projects.first
    project_b = org.projects.create!(name: "B")
    membership = org.memberships.find_by(user: owner)
    sign_in_as!(owner)

    post switch_project_path(project_b.id)
    assert_equal project_b.id, membership.reload.current_project_id

    project_b.destroy

    get dashboard_path
    assert_response :ok
    assert_match project_a.name, response.body
  end

  test "a member without access to a project is blocked from switching to it or admin pages" do
    owner = make_user!("owner6")
    org = owner.organization
    project_a = org.projects.first
    project_b = org.projects.create!(name: "B")

    viewer = User.create!(github_uid: "uid-viewer6", github_login: "viewer6", email: "viewer6@example.com")
    viewer_membership = Membership.create!(organization: org, user: viewer, role: "member")
    ProjectGrant.create!(membership: viewer_membership, project: project_a, level: "viewer")

    sign_in_as!(viewer)

    get dashboard_path
    assert_response :ok

    post switch_project_path(project_b.id)
    assert_response :not_found

    get projects_path
    assert_redirected_to dashboard_path
    follow_redirect!
    assert_match "You don&#39;t have permission to do that.", response.body
  end

  test "non-admin members cannot create projects" do
    owner = make_user!("owner7")
    org = owner.organization
    project = org.projects.first

    member = User.create!(github_uid: "uid-member7", github_login: "member7", email: "member7@example.com")
    member_membership = Membership.create!(organization: org, user: member, role: "member")
    ProjectGrant.create!(membership: member_membership, project: project, level: "viewer")

    sign_in_as!(member)

    assert_no_difference "Project.count" do
      post projects_path, params: { project: { name: "New" } }
    end
    assert_redirected_to dashboard_path
  end
end
