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
    assert_redirected_to sign_in_path
  end

  test "an empty index keeps the table header and puts the empty state in a row" do
    sign_in!

    get events_path
    assert_response :ok
    assert_select "table thead th", text: "Received"
    assert_select "table tbody td[colspan=4]", text: /No events yet/
    assert_select "table tbody a[href=?]", sources_path, text: "View sources"
    # No rows means no bulk-replay form, no selection bar, no checkbox column.
    assert_select "form[action=?]", bulk_replay_events_path, count: 0
    assert_select "input[type=checkbox]", count: 0
  end

  test "a read-only member still gets the empty state's navigation link" do
    sign_in!
    project = current_project
    viewer = User.create!(github_uid: "uid-eviewer", github_login: "eviewer", email: "eviewer@example.com")
    ProjectGrant.create!(membership: Membership.create!(organization: project.organization, user: viewer, role: "member"),
                         project: project, level: "viewer")
    reset!
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new(
      provider: "github", uid: viewer.github_uid,
      info: { nickname: viewer.github_login, name: nil, email: viewer.email, image: nil }
    )
    sign_in!

    get events_path
    assert_response :ok
    # Following a link is not editing, so it is not gated behind can_edit?.
    assert_select "table tbody a[href=?]", sources_path, text: "View sources"
    assert_no_match "Ask a project editor", response.body
  end

  test "an empty filtered index says so and offers to clear the filters" do
    sign_in!

    get events_path(status: "failed")
    assert_response :ok
    assert_select "table tbody td[colspan=4]", text: /No events match these filters/
    assert_select "table tbody a[href=?]", events_path, text: "Clear filters"
  end

  test "index lists the current project's events with delivery summary" do
    sign_in!
    event = build_event!(current_project)
    get events_path
    assert_response :ok
    assert_select "td", text: "GitHub"
    assert_match "1/1 delivered", response.body
    assert_select "a[href=?]", event_path(event)
    # The received cell is a <time> nested in the row link: the link stays the
    # only tab stop, and the ISO instant is there for the client to localise.
    assert_select "a[href=?] time[datetime=?]", event_path(event),
                  event.received_at.utc.iso8601, text: "Just now"
    assert_select "a[href=?] time[tabindex]", event_path(event), count: 0
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
