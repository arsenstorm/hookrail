require "test_helper"

class RetryFlowTest < ActionDispatch::IntegrationTest
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

  # source + destination + connection + event under `project`. Returns [event, connection, destination].
  def build_delivery!(project, url: "https://dest.test/hook")
    source      = Source.create!(project: project, name: "GitHub")
    destination = Destination.create!(project: project, name: "API", url: url)
    connection  = Connection.create!(project: project, source: source, destination: destination)
    event = Event.create!(source: source, http_method: "POST", path: "/wh", received_at: Time.current,
                          headers: { "Content-Type" => "application/json" }, body: %({"x":1}))
    [ event, connection, destination ]
  end

  def add_attempt!(event, connection, status:, number: 1)
    Attempt.create!(event: event, connection: connection, attempt_number: number,
                    attempted_at: Time.current, status: status)
  end

  test "dead delivery shows a Retry control; succeeded shows none" do
    sign_in!
    event, connection, _ = build_delivery!(current_project)
    add_attempt!(event, connection, status: :dead)
    get event_path(event)
    assert_response :ok
    assert_select "form[action=?]", event_retries_path(event)

    ev2, conn2, _ = build_delivery!(current_project, url: "https://dest2.test/hook")
    add_attempt!(ev2, conn2, status: :succeeded)
    get event_path(ev2)
    assert_response :ok
    assert_select "form[action=?]", event_retries_path(ev2), count: 0
  end

  test "retry enqueues delivery and creates the next attempt without collision" do
    sign_in!
    event, connection, destination = build_delivery!(current_project)
    add_attempt!(event, connection, status: :dead, number: 6)
    stub = stub_request(:post, destination.url).to_return(status: 200, body: "ok")

    assert_enqueued_with(job: DeliverEventJob, args: [ event.id, connection.id ]) do
      post event_retries_path(event), params: { connection_id: connection.id }
    end
    assert_redirected_to event_path(event)

    perform_enqueued_jobs
    numbers = Attempt.where(event: event, connection: connection).order(:attempt_number).pluck(:attempt_number)
    assert_equal [ 6, 7 ], numbers
    assert_requested stub, times: 1
    assert Attempt.where(event: event, connection: connection).order(:attempt_number).last.succeeded?
  end

  test "no double success: a succeeded pair performs no further HTTP on re-run" do
    sign_in!
    event, connection, destination = build_delivery!(current_project)
    add_attempt!(event, connection, status: :succeeded, number: 1)
    stub = stub_request(:post, destination.url).to_return(status: 200)

    perform_enqueued_jobs { DeliverEventJob.perform_later(event.id, connection.id) }

    assert_not_requested stub
    assert_equal 1, Attempt.where(event: event, connection: connection).count
  end

  test "no double trigger: a second claim before the job runs does not enqueue again" do
    sign_in!
    event, connection, destination = build_delivery!(current_project)
    add_attempt!(event, connection, status: :dead, number: 1)
    stub_request(:post, destination.url).to_return(status: 200)

    post event_retries_path(event), params: { connection_id: connection.id }
    assert_no_enqueued_jobs only: DeliverEventJob do
      post event_retries_path(event), params: { connection_id: connection.id }
    end
  end

  test "cannot retry another project's delivery" do
    sign_in!
    event, connection, _ = build_delivery!(create_test_project!)
    add_attempt!(event, connection, status: :dead)
    assert_no_enqueued_jobs do
      post event_retries_path(event), params: { connection_id: connection.id }
    end
    assert_response :not_found
  end

  test "unauthenticated retry redirects to login" do
    project = create_test_project!
    event, connection, _ = build_delivery!(project)
    add_attempt!(event, connection, status: :dead)
    post event_retries_path(event), params: { connection_id: connection.id }
    assert_redirected_to login_path
  end
end
