require "test_helper"

class ReplayUiTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

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

  # source + destination + connection under `project`. Returns [source, connection].
  def build_connection!(project, name: SecureRandom.hex(3))
    source      = Source.create!(project: project, name: "S-#{name}")
    destination = Destination.create!(project: project, name: "D-#{name}", url: "https://#{name}.test/hook")
    connection  = Connection.create!(project: project, source: source, destination: destination)
    [ source, connection ]
  end

  def make_event!(source, connection = nil, status: :succeeded, **attempt_attrs)
    event = Event.create!(source: source, http_method: "POST", path: "/wh", received_at: Time.current,
                          headers: { "Content-Type" => "application/json" }, body: %({"x":1}))
    if connection
      Attempt.create!({ event: event, connection: connection, attempt_number: 1,
                        attempted_at: Time.current, status: status }.merge(attempt_attrs))
    end
    event
  end

  test "the events list shows the replay control with the project's connections" do
    sign_in!
    source, connection = build_connection!(current_project, name: "alpha")
    make_event!(source, connection)

    get events_path
    assert_response :ok
    assert_match "Replay filtered events to", response.body
    assert_match "S-alpha → D-alpha", response.body
    assert_match bulk_replay_events_path, response.body
  end

  test "bulk replay enqueues the filtered set and redirects with a count" do
    sign_in!
    source_a, conn_a = build_connection!(current_project)
    make_event!(source_a, conn_a)
    make_event!(source_a, conn_a)

    source_b, conn_b = build_connection!(current_project)
    make_event!(source_b, conn_b)

    assert_enqueued_jobs(2, only: DeliverEventJob) do
      post bulk_replay_events_path, params: { source_id: source_a.id, connection_id: conn_a.id }
    end

    assert_equal 2, Attempt.where(connection: conn_a, replay: true).count
    assert_equal 0, Attempt.where(connection: conn_b, replay: true).count

    assert_redirected_to events_path(source_id: source_a.id.to_s)
    follow_redirect!
    assert_response :ok
    assert_match "Replaying 2 events.", response.body
  end

  test "a replayed attempt renders the replay pill on the event page" do
    sign_in!
    source, connection = build_connection!(current_project)
    replayed = make_event!(source, connection, replay: true)
    plain    = make_event!(source, connection)

    get event_path(replayed)
    assert_response :ok
    assert_match ">replay<", response.body

    get event_path(plain)
    assert_response :ok
    assert_no_match ">replay<", response.body
  end

  test "no replay control when the project has no connections" do
    sign_in!
    source = current_project.sources.create!(name: "Lonely")
    make_event!(source)

    get events_path
    assert_response :ok
    assert_no_match "Replay filtered events to", response.body
  end

  test "unauthenticated replay redirects to login" do
    assert_no_enqueued_jobs do
      post bulk_replay_events_path, params: { connection_id: 1 }
    end
    assert_redirected_to login_path
  end
end
