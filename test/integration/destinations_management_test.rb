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

  test "index shows the empty state when there are no destinations" do
    sign_in!
    get destinations_path
    assert_response :ok
    assert_match "No destinations yet", response.body
    assert_match new_destination_path, response.body
  end

  test "index lists destinations in the table" do
    sign_in!
    d = current_project.destinations.create!(name: "API", url: "https://api.test/hook")
    get destinations_path
    assert_no_match "No destinations yet", response.body
    assert_match "API", response.body
    assert_match "https://api.test/hook", response.body
    assert_match edit_destination_path(d), response.body
    # Row height parity with the sources table, and the URL still truncates inside it.
    assert_match "flex min-h-10 items-center", response.body
    assert_match(/class="block max-w-xs min-w-0 truncate[^"]*"\s+title="https:\/\/api.test\/hook"/, response.body)
  end

  test "index badges a CLI destination instead of showing a URL" do
    sign_in!
    current_project.destinations.create!(name: "Laptop", kind: "cli")
    get destinations_path
    assert_match "Local CLI session", response.body
  end

  test "the auth fields reveal on the selected auth type" do
    sign_in!
    get new_destination_path
    assert_match(/data-controller="reveal"/, response.body)
    assert_match(/data-reveal-target="select"/, response.body)
    assert_match(/data-action="reveal#update"/, response.body)
    # Nothing selected yet, so both credential sections are hidden server-side.
    assert_match(/data-reveal-name="bearer"[^>]*hidden/, response.body)
    assert_match(/data-reveal-name="basic"[^>]*hidden/, response.body)
  end

  test "edit reveals only the configured auth type's fields" do
    sign_in!
    d = current_project.destinations.create!(name: "API", url: "https://api.test/hook",
                                             auth: { "type" => "bearer", "token" => "t0ken" })
    get edit_destination_path(d)
    assert_no_match(/data-reveal-name="bearer"[^>]*hidden/, response.body)
    assert_match(/data-reveal-name="basic"[^>]*hidden/, response.body)
  end

  test "advanced disclosure is collapsed until headers or a rate limit exist" do
    sign_in!
    plain = current_project.destinations.create!(name: "API", url: "https://api.test/hook")
    get edit_destination_path(plain)
    assert_match "Advanced", response.body
    assert_no_match(/<details[^>]*\sopen/, response.body)

    configured = current_project.destinations.create!(name: "API 2", url: "https://api2.test/hook",
                                                      headers: { "X-Api-Key" => "abc" })
    get edit_destination_path(configured)
    assert_match(/<details class="group" open/, response.body)
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
    assert_redirected_to sign_in_path
  end
end
