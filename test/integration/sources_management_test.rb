require "test_helper"

class SourcesManagementTest < ActionDispatch::IntegrationTest
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

  test "creates a source" do
    sign_in!
    assert_difference -> { current_project.sources.count }, 1 do
      post sources_path, params: { source: { name: "GitHub" } }
    end
    assert_redirected_to source_path(current_project.sources.order(:created_at).last)
  end

  test "blank name is rejected with 422" do
    sign_in!
    assert_no_difference -> { Source.count } do
      post sources_path, params: { source: { name: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "show reveals the ingest URL with the token" do
    sign_in!
    source = current_project.sources.create!(name: "GH")
    get source_path(source)
    assert_response :ok
    assert_match ingest_url(token: source.token), response.body
  end

  test "show page guards destroy with a confirm" do
    sign_in!
    source = current_project.sources.create!(name: "GH")
    get source_path(source)
    assert_match "data-turbo-confirm", response.body
  end

  test "rotating the token invalidates the old ingest URL and enables the new one" do
    sign_in!
    source = current_project.sources.create!(name: "GH")
    old = source.token
    patch rotate_token_source_path(source)
    source.reload
    assert_not_equal old, source.token

    post "/ingest/#{old}"
    assert_response :not_found

    assert_difference -> { source.events.count }, 1 do
      post "/ingest/#{source.token}"
    end
    assert_response :ok
  end

  test "deleting a source cascades its events" do
    sign_in!
    source = current_project.sources.create!(name: "GH")
    source.events.create!(http_method: "POST", path: "/wh", received_at: Time.current, headers: {}, body: "x")
    assert_difference -> { Source.count }, -1 do
      assert_difference -> { Event.count }, -1 do
        delete source_path(source)
      end
    end
    assert_redirected_to sources_path
  end

  test "another project's source is not found" do
    sign_in!
    other = create_test_project!.sources.create!(name: "Theirs")
    get source_path(other)
    assert_response :not_found
    patch rotate_token_source_path(other)
    assert_response :not_found
    delete source_path(other)
    assert_response :not_found
  end

  test "unauthenticated requests redirect to login" do
    get sources_path
    assert_redirected_to login_path
  end
end
