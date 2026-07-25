require "test_helper"

class BulkRetryTest < ActionDispatch::IntegrationTest
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
  def build_connection!(project, url: "https://dest-#{SecureRandom.hex(3)}.test/hook")
    source      = Source.create!(project: project, name: "S-#{SecureRandom.hex(3)}")
    destination = Destination.create!(project: project, name: "D-#{SecureRandom.hex(3)}", url: url)
    connection  = Connection.create!(project: project, source: source, destination: destination)
    [ source, connection ]
  end

  # An event on `source` with an attempt of `status` on `connection`. Returns the event.
  def make_event!(source, connection, status:)
    event = Event.create!(source: source, http_method: "POST", path: "/wh", received_at: Time.current,
                          headers: { "Content-Type" => "application/json" }, body: %({"x":1}))
    Attempt.create!(event: event, connection: connection, attempt_number: 1,
                    attempted_at: Time.current, status: status)
    event
  end

  test "retries only failed deliveries in the filtered source" do
    sign_in!
    source_a, conn_a = build_connection!(current_project)
    failed_1 = make_event!(source_a, conn_a, status: :failed)
    failed_2 = make_event!(source_a, conn_a, status: :failed)
    dead_1   = make_event!(source_a, conn_a, status: :dead)
    succeeded_1 = make_event!(source_a, conn_a, status: :succeeded)

    source_b, conn_b = build_connection!(current_project)
    failed_b = make_event!(source_b, conn_b, status: :failed)

    assert_enqueued_jobs(3, only: DeliverEventJob) do
      post bulk_retry_events_path(source_id: source_a.id)
    end

    assert_not Attempt.where(event: failed_b, connection: conn_b).order(:attempt_number).last.pending?
    assert_not Attempt.where(event: succeeded_1, connection: conn_a).order(:attempt_number).last.pending?

    assert_redirected_to events_path(source_id: source_a.id)
    follow_redirect!
    assert_response :ok
  end

  test "operates on the whole filtered set, not one page" do
    sign_in!
    source, connection = build_connection!(current_project)
    (EventsController::PAGE_SIZE + 1).times { make_event!(source, connection, status: :failed) }

    assert_enqueued_jobs(EventsController::PAGE_SIZE + 1, only: DeliverEventJob) do
      post bulk_retry_events_path
    end
  end

  test "does not double-enqueue a pending delivery" do
    sign_in!
    source, connection = build_connection!(current_project)
    event = Event.create!(source: source, http_method: "POST", path: "/wh", received_at: Time.current,
                          headers: {}, body: %({"x":1}))
    Attempt.create!(event: event, connection: connection, attempt_number: 1,
                    attempted_at: Time.current, status: :failed)
    Attempt.create!(event: event, connection: connection, attempt_number: 2,
                    attempted_at: Time.current, status: :pending)

    assert_no_enqueued_jobs do
      post bulk_retry_events_path
    end
  end

  test "does not touch another project's deliveries" do
    other_project = create_test_project!
    source, connection = build_connection!(other_project)
    make_event!(source, connection, status: :failed)

    sign_in!
    assert_no_enqueued_jobs do
      post bulk_retry_events_path
    end
  end

  test "the events list shows the retry button with the count" do
    sign_in!
    source, connection = build_connection!(current_project)
    make_event!(source, connection, status: :failed)
    make_event!(source, connection, status: :failed)

    get events_path
    assert_response :ok
    assert_match "Retry 2 failed deliveries", response.body

    empty_source, _ = build_connection!(current_project)
    get events_path(source_id: empty_source.id)
    assert_response :ok
    assert_no_match "Retry", response.body
  end
end
