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
    event = make_event!(source, connection)

    get events_path
    assert_response :ok
    assert_match "Replay selected events to", response.body
    assert_match "S-alpha → D-alpha", response.body
    assert_match bulk_replay_events_path, response.body
    # The selection column is what feeds the bulk actions.
    assert_match %(name="event_ids[]" value="#{event.id}"), response.body
    # The bar floats over the page, but it has to stay inside the form for the
    # row checkboxes to be its payload.
    assert_select "form[action=?] [data-selection-target=bar] button[type=submit]", bulk_replay_events_path
    assert_select "form[action=?] input[name=?]", bulk_replay_events_path, "event_ids[]"
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

  test "bulk replay with event_ids only touches the selected events" do
    sign_in!
    source, connection = build_connection!(current_project)
    picked  = make_event!(source, connection)
    ignored = make_event!(source, connection)

    assert_enqueued_jobs(1, only: DeliverEventJob) do
      post bulk_replay_events_path, params: { connection_id: connection.id, event_ids: [ picked.id ] }
    end

    assert_equal 1, Attempt.where(event: picked, replay: true).count
    assert_equal 0, Attempt.where(event: ignored, replay: true).count
    follow_redirect!
    assert_match "Replaying 1 event.", response.body
  end

  test "event_ids cannot reach another project's events" do
    other_source, other_connection = build_connection!(create_test_project!)
    outsider = make_event!(other_source, other_connection)

    sign_in!
    source, connection = build_connection!(current_project)
    assert_no_enqueued_jobs do
      post bulk_replay_events_path, params: { connection_id: connection.id, event_ids: [ outsider.id ] }
    end
  end

  test "all_filtered replays everything the filters match, not just the ticked rows" do
    sign_in!
    source, connection = build_connection!(current_project)
    picked = make_event!(source, connection)
    make_event!(source, connection)

    assert_enqueued_jobs(2, only: DeliverEventJob) do
      post bulk_replay_events_path,
           params: { connection_id: connection.id, event_ids: [ picked.id ], all_filtered: "1" }
    end
  end

  test "bulk retry with event_ids only retries the selected events" do
    sign_in!
    source, connection = build_connection!(current_project)
    picked  = make_event!(source, connection, status: :failed)
    ignored = make_event!(source, connection, status: :failed)

    assert_enqueued_jobs(1, only: DeliverEventJob) do
      post bulk_retry_events_path, params: { event_ids: [ picked.id ] }
    end

    assert Attempt.where(event: picked, connection: connection).order(:attempt_number).last.pending?
    assert_not Attempt.where(event: ignored, connection: connection).order(:attempt_number).last.pending?
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
    assert_no_match "Replay selected events to", response.body
  end

  test "unauthenticated replay redirects to login" do
    assert_no_enqueued_jobs do
      post bulk_replay_events_path, params: { connection_id: 1 }
    end
    assert_redirected_to sign_in_path
  end
end
