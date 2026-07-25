require "test_helper"

class RateLimitUiTest < ActionDispatch::IntegrationTest
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

  def destination!(**attrs)
    current_project.destinations.create!(name: "D#{SecureRandom.hex(2)}",
                                         url: "https://d-#{SecureRandom.hex(3)}.test/hook", **attrs)
  end

  test "form shows the rate limit fields" do
    sign_in!
    destination = destination!

    get edit_destination_path(destination)
    assert_response :ok
    assert_match "destination[rate_limit]", response.body
    assert_match "destination[rate_limit_period]", response.body
  end

  test "saving a limit persists it and clearing removes it" do
    sign_in!
    destination = destination!

    patch destination_path(destination),
          params: { destination: { name: destination.name, url: destination.url,
                                   rate_limit: "5", rate_limit_period: "second" } }
    assert_response :redirect
    destination.reload
    assert_equal 5, destination.rate_limit
    assert_equal "second", destination.rate_limit_period

    patch destination_path(destination),
          params: { destination: { name: destination.name, url: destination.url,
                                   rate_limit: "", rate_limit_period: "second" } }
    assert_response :redirect
    destination.reload
    assert_nil destination.rate_limit
    assert_nil destination.rate_limit_period
  end

  test "an out-of-range limit re-renders with the error" do
    sign_in!
    destination = destination!

    patch destination_path(destination),
          params: { destination: { name: destination.name, url: destination.url,
                                   rate_limit: "0", rate_limit_period: "second" } }
    assert_response :unprocessable_entity
    assert_match "must be between 1 and 100 per second", response.body
    assert_nil destination.reload.rate_limit
  end

  test "show displays the limit" do
    sign_in!

    get destination_path(destination!(rate_limit: 5, rate_limit_period: "second"))
    assert_match "5 per second", response.body

    get destination_path(destination!)
    assert_match "Unlimited", response.body
  end
end
