require "test_helper"

class RoutingUiTest < ActionDispatch::IntegrationTest
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

  test "edit page renders the route name with empty fields for a rule-less connection" do
    sign_in!
    connection = connect!

    get edit_connection_path(connection)
    assert_response :ok
    assert_match "GH source", response.body
    assert_match "GH destination", response.body
    assert_match(/<textarea[^>]*name="connection\[rule_headers_text\]"[^>]*>\s*<\/textarea>/, response.body)
    assert_match(/<textarea[^>]*name="connection\[rule_body_text\]"[^>]*>\s*<\/textarea>/, response.body)
    assert_no_match(/value="[^"]+"[^>]*name="connection\[rule_path\]"/, response.body)
  end

  test "update persists the four criteria" do
    sign_in!
    connection = connect!

    patch connection_path(connection), params: { connection: {
      rule_path: "/hooks/*",
      rule_http_method: "POST",
      rule_headers_text: "X-Github-Event: push",
      rule_body_text: "type=invoice.paid"
    } }
    assert_redirected_to connections_path

    assert_equal({
      "path" => "/hooks/*",
      "http_method" => "POST",
      "headers" => { "X-Github-Event" => "push" },
      "body" => { "type" => "invoice.paid" }
    }, connection.reload.routing_rule)
  end

  test "edit page prefills an existing rule" do
    sign_in!
    connection = connect!(routing_rule: {
      "path" => "/hooks/gh",
      "http_method" => "POST",
      "headers" => { "X-Github-Event" => "push" },
      "body" => { "data.object.status" => "succeeded" }
    })

    get edit_connection_path(connection)
    assert_response :ok
    assert_match(/name="connection\[rule_headers_text\]"[^>]*>\s*X-Github-Event: push<\/textarea>/, response.body)
    assert_match(/name="connection\[rule_body_text\]"[^>]*>\s*data\.object\.status=succeeded<\/textarea>/, response.body)
    assert_match(/value="\/hooks\/gh"[^>]*name="connection\[rule_path\]"/, response.body)
    assert_match(/<option selected="selected" value="POST">/, response.body)
  end

  test "blank fields clear the rule and the filtered pill tracks it" do
    sign_in!
    filtered = connect!(name: "Filtered", routing_rule: { "path" => "/hooks/*" })
    plain = connect!(name: "Plain")

    get connections_path
    assert_response :ok
    assert_equal 1, response.body.scan("filtered</span>").size

    patch connection_path(filtered), params: { connection: {
      rule_path: "", rule_http_method: "", rule_headers_text: "", rule_body_text: ""
    } }
    assert_redirected_to connections_path
    assert_equal({}, filtered.reload.routing_rule)
    assert_equal({}, plain.reload.routing_rule)

    get connections_path
    assert_no_match(/filtered<\/span>/, response.body)
  end

  test "unauthenticated edit redirects to login" do
    connection = connect!(create_test_project!)

    get edit_connection_path(connection)
    assert_redirected_to sign_in_path
  end
end
