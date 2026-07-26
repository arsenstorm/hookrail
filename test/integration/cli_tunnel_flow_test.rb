require "test_helper"

class CliTunnelFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ActionCable::TestHelper

  ADD_HEADER_TRANSFORM = <<~JS
    function transform(r) {
      return { headers: r.headers, body: { got: r.body.type } };
    }
  JS

  def make_user!(login)
    user = User.create!(github_uid: "uid-#{login}", github_login: login, email: "#{login}@example.com")
    user.ensure_org_and_project!
    user
  end

  def auth(raw)
    { "Authorization" => "Bearer #{raw}" }
  end

  def ingest!(source, body: '{"a":1}')
    post "/ingest/#{source.token}", params: body, headers: { "Content-Type" => "application/json" }
  end

  setup do
    @owner = make_user!("tunnel-owner")
    @org = @owner.organization
    @project = @org.projects.first
    @token, @raw = CliToken.issue!(user: @owner, organization: @org, name: "listener box")
    @source = @project.sources.create!(name: "Tunnel source")
  end

  def create_listener!
    post "/api/v1/cli/listeners", params: { source: @source.id }, headers: auth(@raw)
    assert_response :created
    body = JSON.parse(response.body)
    [ Connection.find(body["connection_id"]), body ]
  end

  test "creating a listener is idempotent across reconnects" do
    connection, body = create_listener!
    destination = Destination.find(body["destination_id"])
    assert_equal "cli", destination.kind
    assert_equal @source.id, connection.source_id
    assert_equal destination.id, connection.destination_id

    post "/api/v1/cli/listeners", params: { source: @source.id }, headers: auth(@raw)
    assert_response :created
    body2 = JSON.parse(response.body)
    assert_equal body["destination_id"], body2["destination_id"]
    assert_equal body["connection_id"], body2["connection_id"]
  end

  test "an offline listener exhausts the whole retry chain" do
    connection, = create_listener!
    assert_not CliPresence.online?(connection.id)

    perform_enqueued_jobs { ingest!(@source) }

    attempts = Attempt.where(connection: connection).order(:attempt_number)
    assert_equal DeliverEventJob::MAX_ATTEMPTS, attempts.count
    assert attempts.first.failed?
    assert_equal "No CLI session is listening", attempts.first.error
    assert attempts.last.dead?
    assert_equal 0, attempts.delivering.count
  end

  test "an online listener gets exactly one broadcast, stays delivering, and schedules a timeout" do
    connection, = create_listener!
    CliPresence.connect(connection.id)

    messages = capture_broadcasts("cli_connection_#{connection.id}") do
      perform_enqueued_jobs(only: DeliverEventJob) { ingest!(@source) }
    end
    assert_equal 1, messages.size

    attempt = Attempt.where(connection: connection).sole
    assert attempt.delivering?
    assert_equal attempt.id, messages.first["attempt_id"]
    assert_equal 0, messages.first["retry_count"]
    assert messages.first["forward"]["headers"].key?("X-Hookrail-Signature")

    assert_enqueued_with(job: CliAttemptTimeoutJob, args: [ attempt.id, 0 ])
  end

  test "a success result finalizes the attempt, is idempotent, and the queued timeout no-ops" do
    connection, = create_listener!
    CliPresence.connect(connection.id)
    perform_enqueued_jobs(only: DeliverEventJob) { ingest!(@source) }
    attempt = Attempt.where(connection: connection).sole

    post "/api/v1/cli/attempts/#{attempt.id}/result",
         params: { retry_count: 0, status: 200, body_excerpt: "ok", duration_ms: 12 }, headers: auth(@raw)
    assert_response :ok
    assert_equal "succeeded", JSON.parse(response.body)["status"]
    attempt.reload
    assert attempt.succeeded?
    assert_equal 200, attempt.response_status
    assert_equal 0, connection.reload.consecutive_failures

    post "/api/v1/cli/attempts/#{attempt.id}/result",
         params: { retry_count: 0, status: 200, body_excerpt: "ok", duration_ms: 12 }, headers: auth(@raw)
    assert_response :ok
    assert_equal "succeeded", JSON.parse(response.body)["status"]

    assert_no_enqueued_jobs(only: DeliverEventJob) do
      perform_enqueued_jobs(only: CliAttemptTimeoutJob)
    end
    attempt.reload
    assert attempt.succeeded?
  end

  test "a failure result fails the attempt, enqueues a retry, and scrubs a null byte in body_excerpt" do
    connection, = create_listener!
    CliPresence.connect(connection.id)
    perform_enqueued_jobs(only: DeliverEventJob) { ingest!(@source) }
    attempt = Attempt.where(connection: connection).sole

    bad_body = "bad" + 0.chr + "body"
    assert_enqueued_with(job: DeliverEventJob,
                         args: [ attempt.event_id, connection.id, { replay: false, retry_count: 1 } ]) do
      post "/api/v1/cli/attempts/#{attempt.id}/result",
           params: { retry_count: 0, status: 500, body_excerpt: bad_body, error: "boom" }, headers: auth(@raw)
    end
    assert_response :ok
    assert_equal "failed", JSON.parse(response.body)["status"]
    attempt.reload
    assert attempt.failed?
    assert_equal "badbody", attempt.response_body
  end

  test "a timeout fails a stranded attempt, enqueues exactly one retry, and is idempotent" do
    connection, = create_listener!
    CliPresence.connect(connection.id)
    perform_enqueued_jobs(only: DeliverEventJob) { ingest!(@source) }
    attempt = Attempt.where(connection: connection).sole
    assert attempt.delivering?

    assert_enqueued_with(job: DeliverEventJob,
                         args: [ attempt.event_id, connection.id, { replay: false, retry_count: 1 } ]) do
      CliAttemptTimeoutJob.new.perform(attempt.id, 0)
    end
    attempt.reload
    assert attempt.failed?
    assert_equal "CLI session did not respond within 30 seconds", attempt.error

    assert_no_enqueued_jobs(only: DeliverEventJob) do
      CliAttemptTimeoutJob.new.perform(attempt.id, 0)
    end
    attempt.reload
    assert attempt.failed?
  end

  test "a transformed connection broadcasts the transformed body" do
    connection, = create_listener!
    connection.update!(transformation: ADD_HEADER_TRANSFORM)
    CliPresence.connect(connection.id)

    messages = capture_broadcasts("cli_connection_#{connection.id}") do
      perform_enqueued_jobs(only: DeliverEventJob) { ingest!(@source, body: '{"type":"x"}') }
    end

    forwarded_body = JSON.parse(messages.first["forward"]["body"])
    assert_equal({ "got" => "x" }, forwarded_body)
  end

  test "a viewer-only CLI token cannot create a listener" do
    viewer = User.create!(github_uid: "uid-tunnel-viewer", github_login: "tunnel-viewer",
                          email: "tunnel-viewer@example.com")
    membership = Membership.create!(organization: @org, user: viewer, role: "member")
    ProjectGrant.create!(membership: membership, project: @project, level: "viewer")
    _viewer_token, viewer_raw = CliToken.issue!(user: viewer, organization: @org, name: "viewer box")

    post "/api/v1/cli/listeners", params: { source: @source.id }, headers: auth(viewer_raw)
    assert_response :forbidden
  end
end
