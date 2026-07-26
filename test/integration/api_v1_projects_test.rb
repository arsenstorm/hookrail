require "test_helper"

class ApiV1ProjectsTest < ActionDispatch::IntegrationTest
  def issue_key!(org)
    ApiKey.issue!(organization: org, name: "test")
  end

  def auth(raw)
    { "Authorization" => "Bearer #{raw}" }
  end

  test "GET /api/v1/projects with an org API key returns all the org's projects ordered by id" do
    project = create_test_project!
    org = project.organization
    second = org.projects.create!(name: "Second")
    _key, raw = issue_key!(org)

    get "/api/v1/projects", headers: auth(raw)
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal [ { "id" => project.id, "name" => project.name },
                   { "id" => second.id, "name" => second.name } ], body["projects"]
  end

  test "project_id addresses a specific project on reads, and omitting it keeps the first project (back-compat)" do
    project = create_test_project!
    org = project.organization
    second = org.projects.create!(name: "Second")
    Source.create!(project: project, name: "First-Source")
    Source.create!(project: second, name: "Second-Source")
    _key, raw = issue_key!(org)

    get "/api/v1/sources", params: { project_id: second.id }, headers: auth(raw)
    assert_response :ok
    assert_equal [ "Second-Source" ], JSON.parse(response.body)["sources"].map { |s| s["name"] }

    get "/api/v1/sources", headers: auth(raw)
    assert_response :ok
    assert_equal [ "First-Source" ], JSON.parse(response.body)["sources"].map { |s| s["name"] }
  end

  test "project_id from another org 404s, as does a nonexistent id" do
    project = create_test_project!
    org = project.organization
    _key, raw = issue_key!(org)

    other_org_project = create_test_project!

    get "/api/v1/sources", params: { project_id: other_org_project.id }, headers: auth(raw)
    assert_response :not_found
    assert_equal "not_found", JSON.parse(response.body)["error"]["code"]

    get "/api/v1/sources", params: { project_id: 9_999_999 }, headers: auth(raw)
    assert_response :not_found
    assert_equal "not_found", JSON.parse(response.body)["error"]["code"]
  end

  test "CLI-token RBAC: project_id scopes reads to the granted project only" do
    project_a = create_test_project!
    org = project_a.organization
    project_b = org.projects.create!(name: "Project B")

    member = User.create!(github_uid: "uid-member-#{SecureRandom.hex(4)}", github_login: "member")
    membership = Membership.create!(organization: org, user: member, role: "member")
    ProjectGrant.create!(membership: membership, project: project_a, level: "viewer")
    _token, raw = CliToken.issue!(user: member, organization: org, name: "member's box")

    get "/api/v1/sources", params: { project_id: project_a.id }, headers: auth(raw)
    assert_response :ok

    get "/api/v1/sources", params: { project_id: project_b.id }, headers: auth(raw)
    assert_response :forbidden
    assert_equal "You don't have access to this project", JSON.parse(response.body)["error"]["message"]

    get "/api/v1/projects", headers: auth(raw)
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal [ { "id" => project_a.id, "name" => project_a.name } ], body["projects"]
  end

  test "POST creating a source with project_id in the body params creates it in the addressed project" do
    project = create_test_project!
    org = project.organization
    second = org.projects.create!(name: "Second")
    _key, raw = issue_key!(org)

    post "/api/v1/sources", params: { project_id: second.id, source: { name: "New Source" } },
                             headers: auth(raw), as: :json
    assert_response :created

    source = Source.find_by(name: "New Source")
    assert_equal second.id, source.project_id
  end
end
