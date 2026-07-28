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

  test "status action moves a connection through its states" do
    sign_in!
    s, d = pair!(current_project)
    c = current_project.connections.create!(source: s, destination: d)

    patch status_connection_path(c, status: "paused")
    assert_redirected_to connections_path
    assert_equal "paused", c.reload.status

    patch status_connection_path(c, status: "active")
    assert_redirected_to connections_path
    assert_equal "active", c.reload.status

    patch status_connection_path(c, status: "disabled")
    assert_redirected_to connections_path
    assert_equal "disabled", c.reload.status

    patch status_connection_path(c, status: "bogus")
    assert_redirected_to connections_path
    assert_equal "disabled", c.reload.status
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

  test "index shows the empty state when there are no connections" do
    sign_in!
    get connections_path
    assert_response :ok
    assert_match "No connections yet", response.body
    assert_match new_connection_path, response.body
  end

  test "index badges a paused connection" do
    sign_in!
    s, d = pair!(current_project)
    current_project.connections.create!(source: s, destination: d, status: "paused")
    get connections_path
    assert_no_match "No connections yet", response.body
    assert_match "paused", response.body
    assert_match "bg-amber", response.body
    assert_match "flex min-h-10 items-center", response.body
    assert_match s.name, response.body
    assert_match d.name, response.body
  end

  test "index badges an active connection by health, not by status" do
    sign_in!
    s, d = pair!(current_project)
    current_project.connections.create!(source: s, destination: d)
    get connections_path
    assert_match ">healthy<", response.body
    assert_no_match(/>active</, response.body)
  end

  test "index badges an unhealthy active connection as unhealthy only" do
    sign_in!
    s, d = pair!(current_project)
    current_project.connections.create!(source: s, destination: d, unhealthy_since: 2.hours.ago)
    get connections_path
    assert_match ">unhealthy<", response.body
    assert_match "failing since", response.body
    assert_no_match(/>healthy</, response.body)
    assert_no_match(/>active</, response.body)
  end

  test "index keeps the health line under a paused connection" do
    sign_in!
    s, d = pair!(current_project)
    current_project.connections.create!(source: s, destination: d, status: "paused", unhealthy_since: 2.hours.ago)
    get connections_path
    row = css_select("tbody").to_s
    assert_match ">paused<", row
    assert_match ">unhealthy<", row
    assert_match "failing since", row
  end

  test "index drops the health line for a disabled connection" do
    sign_in!
    s, d = pair!(current_project)
    current_project.connections.create!(source: s, destination: d, status: "disabled", unhealthy_since: 2.hours.ago)
    get connections_path
    # A disabled connection isn't delivering, so its last health is stale noise —
    # dropped from the row and from the banner above the table alike.
    row = css_select("tbody").to_s
    assert_match ">disabled<", row
    assert_no_match(/unhealthy/, row)
    assert_no_match(/failing since/, row)
    assert_no_match "failing delivery", response.body
  end

  test "new offers both creation links when there is nothing to connect" do
    sign_in!
    get new_connection_path
    assert_match "Nothing to connect yet", response.body
    assert_match new_source_path, response.body
    assert_match new_destination_path, response.body
  end

  test "edit collapses transformation and retry policy" do
    sign_in!
    s, d = pair!(current_project)
    c = current_project.connections.create!(source: s, destination: d)
    get edit_connection_path(c)
    assert_match "Transformation", response.body
    assert_match "Retry policy", response.body
    assert_no_match(/<details[^>]*\sopen/, response.body)
  end

  test "edit opens the transformation disclosure when one is set" do
    sign_in!
    s, d = pair!(current_project)
    c = current_project.connections.create!(source: s, destination: d,
                                            transformation: "function transform(r) { return r; }")
    get edit_connection_path(c)
    assert_match(/<details class="group" open/, response.body)
  end

  test "another project's connection cannot be toggled or deleted" do
    sign_in!
    other = create_test_project!
    s, d = pair!(other)
    c = other.connections.create!(source: s, destination: d)
    patch status_connection_path(c, status: "paused")
    assert_response :not_found
    delete connection_path(c)
    assert_response :not_found
  end

  test "unauthenticated requests redirect to login" do
    get connections_path
    assert_redirected_to sign_in_path
  end
end
