require "test_helper"

class ConnectionStatusUiTest < ActionDispatch::IntegrationTest
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

  def connection!(status: "active")
    project = current_project
    source = project.sources.create!(name: "S#{SecureRandom.hex(2)}")
    destination = project.destinations.create!(name: "D#{SecureRandom.hex(2)}",
                                               url: "https://d-#{SecureRandom.hex(3)}.test/hook")
    project.connections.create!(source: source, destination: destination, status: status)
  end

  def make_event!(source)
    source.events.create!(http_method: "POST", path: "/wh", received_at: Time.current,
                          headers: { "Content-Type" => "application/json" }, body: '{"a":1}')
  end

  test "index shows state badges and the right buttons per state" do
    sign_in!
    connection!(status: "active")
    connection!(status: "paused")
    connection!(status: "disabled")

    get connections_path
    assert_response :ok
    assert_match "Pause", response.body
    assert_match "Disable", response.body
    assert_match "Resume", response.body
    assert_match "Enable", response.body
    assert_match "paused", response.body
    assert_match "disabled", response.body
  end

  test "pausing and resuming shows the right notices" do
    sign_in!
    connection = connection!

    patch status_connection_path(connection, status: "paused")
    follow_redirect!
    assert_match "Connection paused.", response.body

    patch status_connection_path(connection, status: "active")
    follow_redirect!
    assert_match "Connection resumed.", response.body
  end

  test "disabling shows its notice and confirmable button exists" do
    sign_in!
    connection = connection!

    patch status_connection_path(connection, status: "disabled")
    follow_redirect!
    assert_match "Connection disabled.", response.body

    # a disabled row offers only Enable, so the confirmable Disable button
    # lives on a still-active connection
    connection!
    get connections_path
    assert_match "Held and pending deliveries are cancelled.", response.body
  end

  test "unknown status is rejected with an alert" do
    sign_in!
    connection = connection!

    patch status_connection_path(connection, status: "bogus")
    follow_redirect!
    assert_match "Unknown status.", response.body
    assert_equal "active", connection.reload.status
  end

  test "bulk replay against a paused connection is refused with an alert" do
    sign_in!
    connection = connection!(status: "paused")
    make_event!(connection.source)

    post bulk_replay_events_path(connection_id: connection.id)
    follow_redirect!
    assert_match "Resume it before replaying", response.body
  end

  test "manual retry against a paused connection is refused with an alert" do
    sign_in!
    connection = connection!(status: "paused")
    event = make_event!(connection.source)
    Attempt.create!(event: event, connection: connection, attempt_number: 1,
                    attempted_at: Time.current, status: "failed")

    post event_retries_path(event, connection_id: connection.id)
    follow_redirect!
    assert_match "deliveries are stopped", response.body

    get event_path(event)
    assert_no_match(/action="#{Regexp.escape(event_retries_path(event))}"/, response.body)
  end
end
