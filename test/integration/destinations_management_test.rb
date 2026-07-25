require "test_helper"

class DestinationsManagementTest < ActionDispatch::IntegrationTest
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

  test "creates a destination" do
    sign_in!
    assert_difference -> { current_project.destinations.count }, 1 do
      post destinations_path, params: { destination: { name: "API", url: "https://api.test/hook", headers_text: "" } }
    end
    assert_redirected_to destination_path(current_project.destinations.order(:created_at).last)
  end

  test "custom headers text is parsed into the jsonb map" do
    sign_in!
    post destinations_path, params: { destination: { name: "API", url: "https://api.test/hook", headers_text: "X-Api-Key: abc\nX-Env: prod" } }
    d = current_project.destinations.order(:created_at).last
    assert_equal({ "X-Api-Key" => "abc", "X-Env" => "prod" }, d.headers)
  end

  test "blank url is rejected with 422" do
    sign_in!
    assert_no_difference -> { Destination.count } do
      post destinations_path, params: { destination: { name: "API", url: "", headers_text: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "show reveals the signing secret" do
    sign_in!
    d = current_project.destinations.create!(name: "API", url: "https://api.test/hook")
    get destination_path(d)
    assert_response :ok
    assert_match d.signing_secret, response.body
  end

  test "update changes url and headers" do
    sign_in!
    d = current_project.destinations.create!(name: "API", url: "https://old.test", headers: { "A" => "1" })
    patch destination_path(d), params: { destination: { name: "API", url: "https://new.test", headers_text: "B: 2" } }
    d.reload
    assert_equal "https://new.test", d.url
    assert_equal({ "B" => "2" }, d.headers)
  end

  test "rotating the signing secret changes it" do
    sign_in!
    d = current_project.destinations.create!(name: "API", url: "https://api.test/hook")
    old = d.signing_secret
    patch rotate_secret_destination_path(d)
    d.reload
    assert_not_equal old, d.signing_secret
    assert_redirected_to destination_path(d)
  end

  test "another project's destination is not found" do
    sign_in!
    other = create_test_project!.destinations.create!(name: "Theirs", url: "https://x.test")
    get destination_path(other)
    assert_response :not_found
    delete destination_path(other)
    assert_response :not_found
  end

  test "unauthenticated requests redirect to login" do
    get destinations_path
    assert_redirected_to login_path
  end
end
