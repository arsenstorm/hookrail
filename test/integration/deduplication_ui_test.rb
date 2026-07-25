require "test_helper"

class DeduplicationUiTest < ActionDispatch::IntegrationTest
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

  def source!(**attrs)
    current_project.sources.create!(name: "S#{SecureRandom.hex(2)}", **attrs)
  end

  def event!(source, **attrs)
    source.events.create!(http_method: "POST", path: "/wh", received_at: Time.current,
                          headers: {}, body: "{}", **attrs)
  end

  test "form shows the dedupe fields" do
    sign_in!

    get edit_source_path(source!)
    assert_response :ok
    assert_match "source[dedupe_window]", response.body
    assert_match "source[dedupe_key]", response.body
  end

  test "saving dedupe persists it and clearing removes it" do
    sign_in!
    source = source!

    patch source_path(source),
          params: { source: { name: source.name, dedupe_window: "300", dedupe_key: "X-Id" } }
    assert_response :redirect
    assert_equal({ "window" => 300, "key" => "X-Id" }, source.reload.dedupe)

    patch source_path(source),
          params: { source: { name: source.name, dedupe_window: "", dedupe_key: "" } }
    assert_response :redirect
    assert_not source.reload.dedupe_enabled?
  end

  test "an out-of-range window re-renders with the error" do
    sign_in!
    source = source!

    patch source_path(source),
          params: { source: { name: source.name, dedupe_window: "0", dedupe_key: "X-Id" } }
    assert_response :unprocessable_entity
    assert_match "window must be an integer between 1 and 86400 seconds", response.body
    assert_not source.reload.dedupe_enabled?
  end

  test "the events list badges duplicates and filters on them" do
    sign_in!
    source = source!
    original = event!(source)
    dup = event!(source, duplicate: true, dedupe_key: "sha256:x")

    get events_path
    assert_response :ok
    # Anchored on the badge markup: a bare "duplicate" also matches the status filter's own option.
    assert_select "tbody tr span.rounded-full", text: "duplicate", count: 1

    get events_path(status: "duplicate")
    assert_response :ok
    assert_match event_path(dup), response.body
    assert_no_match(/#{Regexp.escape(event_path(original))}"/, response.body)
  end
end
