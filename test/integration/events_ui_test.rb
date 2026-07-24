require "test_helper"

class EventsUiTest < ActionDispatch::IntegrationTest
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

  # One event with a single succeeded attempt, all under `project`.
  def build_event!(project, method: "POST", path: "/wh")
    source      = Source.create!(project: project, name: "GitHub")
    destination = Destination.create!(project: project, name: "My API", url: "https://api.example.com/hook")
    connection  = Connection.create!(project: project, source: source, destination: destination)
    event = Event.create!(source: source, http_method: method, path: path, received_at: Time.current,
                          headers: { "Content-Type" => "application/json" }, body: %({"hello":"world"}))
    Attempt.create!(event: event, connection: connection, attempt_number: 1, attempted_at: Time.current,
                    status: "succeeded", response_status: 200, duration_ms: 42, response_body: "ok")
    event
  end

  test "unauthenticated events index redirects to login" do
    get events_path
    assert_redirected_to login_path
  end

  test "index lists the current project's events with delivery summary" do
    sign_in!
    event = build_event!(current_project)
    get events_path
    assert_response :ok
    assert_select "td", text: "GitHub"
    assert_match "1/1 delivered", response.body
    assert_select "a[href=?]", event_path(event)
  end

  test "show renders request details and delivery attempts" do
    sign_in!
    event = build_event!(current_project)
    get event_path(event)
    assert_response :ok
    assert_match "Content-Type", response.body
    assert_match "{&quot;hello&quot;:&quot;world&quot;}", response.body
    assert_match "My API", response.body
    assert_match "200", response.body
  end

  test "cannot view another project's event" do
    sign_in!
    other_event = build_event!(create_test_project!)
    get event_path(other_event)
    assert_response :not_found
  end

  test "index excludes other projects' events" do
    sign_in!
    mine  = build_event!(current_project, path: "/mine")
    other = build_event!(create_test_project!, path: "/theirs")
    get events_path
    assert_response :ok
    assert_select "a[href=?]", event_path(mine)
    assert_select "a[href=?]", event_path(other), count: 0
  end
end
