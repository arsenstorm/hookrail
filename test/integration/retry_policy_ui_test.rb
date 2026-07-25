require "test_helper"

class RetryPolicyUiTest < ActionDispatch::IntegrationTest
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

  def connection!(retry_policy: nil)
    project = current_project
    source = project.sources.create!(name: "S#{SecureRandom.hex(2)}")
    destination = project.destinations.create!(name: "D#{SecureRandom.hex(2)}",
                                               url: "https://d-#{SecureRandom.hex(3)}.test/hook")
    project.connections.create!(source: source, destination: destination, retry_policy: retry_policy)
  end

  test "edit page shows the retry policy fields" do
    sign_in!
    connection = connection!(retry_policy: { "strategy" => "linear", "interval" => 60, "max_attempts" => 3 })

    get edit_connection_path(connection)
    assert_response :ok
    assert_match "connection[retry_strategy]", response.body
    assert_match "connection[retry_interval]", response.body
    assert_match "connection[retry_max_attempts]", response.body
    assert_match(/value="60"/, response.body)
    assert_match(/value="3"/, response.body)
  end

  test "saving a policy persists it and clearing removes it" do
    sign_in!
    connection = connection!

    patch connection_path(connection),
          params: { connection: { retry_strategy: "linear", retry_interval: "60", retry_max_attempts: "3" } }
    assert_response :redirect
    assert_equal({ "strategy" => "linear", "interval" => 60, "max_attempts" => 3 }, connection.reload.retry_policy)

    patch connection_path(connection),
          params: { connection: { retry_strategy: "", retry_interval: "", retry_max_attempts: "" } }
    assert_response :redirect
    assert_nil connection.reload.retry_policy
  end

  test "an invalid policy re-renders the form with the error" do
    sign_in!
    connection = connection!

    patch connection_path(connection),
          params: { connection: { retry_strategy: "linear", retry_interval: "0", retry_max_attempts: "3" } }
    assert_response :unprocessable_entity
    assert_match "interval must be a positive integer", response.body
    assert_nil connection.reload.retry_policy
  end

  test "a policy exceeding the caps is rejected" do
    sign_in!
    connection = connection!

    patch connection_path(connection),
          params: { connection: { retry_strategy: "exponential", retry_interval: "3600", retry_max_attempts: "20" } }
    assert_response :unprocessable_entity
    assert_match "schedule spans more than 7 days", response.body
    assert_nil connection.reload.retry_policy
  end
end
