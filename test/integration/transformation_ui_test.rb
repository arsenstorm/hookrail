require "test_helper"

class TransformationUiTest < ActionDispatch::IntegrationTest
  MARKER_TRANSFORM = <<~JS
    function transform(r) { return { headers: {}, body: "marker-42-" + r.body.type }; }
  JS

  THROWING_TRANSFORM = 'function transform(r) { throw new Error("kaboom"); }'

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

  def connect!(project = current_project, name: "GH", **attrs)
    project.connections.create!(
      source: project.sources.create!(name: "#{name} source"),
      destination: project.destinations.create!(name: "#{name} destination", url: "https://example.com/#{name}"),
      **attrs
    )
  end

  def make_event!(source, body: %({"type":"x"}))
    Event.create!(source: source, http_method: "POST", path: "/wh", received_at: Time.current,
                  headers: { "Content-Type" => "application/json" }, body: body)
  end

  test "edit page renders the transformation textarea and preview controls" do
    sign_in!
    connection = connect!
    event = make_event!(connection.source)

    get edit_connection_path(connection)
    assert_response :ok
    assert_match(/<textarea[^>]*name="connection\[transformation\]"/, response.body)
    assert_match(/<select[^>]*name="preview_event_id"/, response.body)
    assert_match "##{event.id} ", response.body
    assert_match(/name="preview"[^>]*value="Preview"/, response.body)
  end

  test "update saves the transformation alongside the rule" do
    sign_in!
    connection = connect!

    patch connection_path(connection), params: { connection: {
      rule_path: "/hooks/*", rule_http_method: "POST", rule_headers_text: "", rule_body_text: "",
      transformation: MARKER_TRANSFORM
    } }
    assert_redirected_to connections_path
    follow_redirect!
    assert_match "Connection updated.", response.body

    connection.reload
    assert_equal MARKER_TRANSFORM, connection.transformation
    assert_equal "/hooks/*", connection.routing_rule["path"]
  end

  test "syntax-broken transformation code re-renders with the validation error" do
    sign_in!
    connection = connect!

    patch connection_path(connection), params: { connection: {
      rule_path: "", rule_http_method: "", rule_headers_text: "", rule_body_text: "",
      transformation: "function transform(r) {"
    } }
    assert_response :unprocessable_entity
    assert_match "Transformation", response.body
    assert_nil connection.reload.transformation
  end

  test "preview runs the transform without saving it" do
    sign_in!
    connection = connect!
    event = make_event!(connection.source)

    patch connection_path(connection), params: {
      preview: "Preview", preview_event_id: event.id,
      connection: { rule_path: "", rule_http_method: "", rule_headers_text: "", rule_body_text: "",
                    transformation: MARKER_TRANSFORM }
    }
    assert_response :ok
    assert_match "marker-42-x", response.body
    assert_nil connection.reload.transformation
  end

  test "preview with throwing code renders the error" do
    sign_in!
    connection = connect!
    event = make_event!(connection.source)

    patch connection_path(connection), params: {
      preview: "Preview", preview_event_id: event.id,
      connection: { rule_path: "", rule_http_method: "", rule_headers_text: "", rule_body_text: "",
                    transformation: THROWING_TRANSFORM }
    }
    assert_response :ok
    assert_match "kaboom", response.body
  end

  test "event page shows the transform-error pill and the transformed request" do
    sign_in!
    connection = connect!
    event = make_event!(connection.source)
    Attempt.create!(event: event, connection: connection, attempt_number: 1,
                    attempted_at: Time.current, status: :failed, error: "TransformationError: boom")
    Attempt.create!(event: event, connection: connection, attempt_number: 2,
                    attempted_at: Time.current, status: :succeeded,
                    transformed_headers: { "X-Env" => "test" }, transformed_body: '{"got":"x"}')

    get event_path(event)
    assert_response :ok
    assert_match "transform error", response.body
    assert_match "Transformed request", response.body
    assert_match "X-Env", response.body
    assert_match "{&quot;got&quot;:&quot;x&quot;}", response.body
  end
end
