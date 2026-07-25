require "test_helper"

class ConnectionsManagementTest < ActionDispatch::IntegrationTest
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

  # source + destination under the given project
  def pair!(project)
    [ project.sources.create!(name: "S#{SecureRandom.hex(2)}"),
      project.destinations.create!(name: "D#{SecureRandom.hex(2)}", url: "https://d.test/hook") ]
  end

  test "creates a connection" do
    sign_in!
    s, d = pair!(current_project)
    assert_difference -> { current_project.connections.count }, 1 do
      post connections_path, params: { connection: { source_id: s.id, destination_id: d.id } }
    end
    assert_redirected_to connections_path
  end

  test "duplicate pair is rejected with 422 and creates no second row" do
    sign_in!
    s, d = pair!(current_project)
    current_project.connections.create!(source: s, destination: d)
    assert_no_difference -> { Connection.count } do
      post connections_path, params: { connection: { source_id: s.id, destination_id: d.id } }
    end
    assert_response :unprocessable_entity
    assert_match "already connected", response.body
  end

  test "toggle flips active" do
    sign_in!
    s, d = pair!(current_project)
    c = current_project.connections.create!(source: s, destination: d, active: true)
    patch toggle_connection_path(c)
    assert_redirected_to connections_path
    assert_equal false, c.reload.active
    patch toggle_connection_path(c)
    assert_equal true, c.reload.active
  end

  test "deleting a connection removes it" do
    sign_in!
    s, d = pair!(current_project)
    c = current_project.connections.create!(source: s, destination: d)
    assert_difference -> { Connection.count }, -1 do
      delete connection_path(c)
    end
    assert_redirected_to connections_path
  end

  test "another project's connection cannot be toggled or deleted" do
    sign_in!
    other = create_test_project!
    s, d = pair!(other)
    c = other.connections.create!(source: s, destination: d)
    patch toggle_connection_path(c)
    assert_response :not_found
    delete connection_path(c)
    assert_response :not_found
  end

  test "unauthenticated requests redirect to login" do
    get connections_path
    assert_redirected_to login_path
  end
end
