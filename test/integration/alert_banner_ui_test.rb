require "test_helper"

class AlertBannerUiTest < ActionDispatch::IntegrationTest
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

  def connect!(project, **attrs)
    project.connections.create!(
      source: project.sources.create!(name: "GH"),
      destination: project.destinations.create!(name: "API", url: "https://api.test/hook")
    ).tap { |c| c.update!(**attrs) if attrs.any? }
  end

  test "dashboard shows the banner for an unhealthy connection" do
    sign_in!
    connect!(current_project, unhealthy_since: 2.hours.ago, consecutive_failures: 5)

    get root_path
    assert_response :ok
    assert_match "GH", response.body
    assert_match "API", response.body
    assert_match "failing for about 2 hours", response.body
  end

  test "connections index shows the banner and the row indicator" do
    sign_in!
    connect!(current_project, unhealthy_since: 2.hours.ago, consecutive_failures: 5)

    get connections_path
    assert_response :ok
    assert_match "failing delivery", response.body
    assert_match "unhealthy", response.body
    assert_match "failing for about 2 hours", response.body
  end

  test "dashboard shows no banner when every connection is healthy" do
    sign_in!
    connect!(current_project)

    get root_path
    assert_response :ok
    assert_no_match "failing delivery", response.body
  end
end
