require "test_helper"

class MetricsUiTest < ActionDispatch::IntegrationTest
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

  def build_connection!
    project = current_project
    suffix = SecureRandom.hex(3)
    source = project.sources.create!(name: "S-#{suffix}")
    destination = project.destinations.create!(name: "D-#{suffix}", url: "https://dest-#{suffix}.test/hook")
    [ source, destination, project.connections.create!(source: source, destination: destination) ]
  end

  def event!(source)
    source.events.create!(http_method: "POST", path: "/wh", received_at: Time.current, headers: {}, body: "{}")
  end

  def attempt!(event, connection, status:, duration_ms: nil)
    Attempt.create!(event: event, connection: connection, attempt_number: 1,
                    status: status, attempted_at: Time.current, duration_ms: duration_ms)
  end

  test "the dashboard renders totals, charts, and latency with 24h default" do
    sign_in!
    source, _destination, connection = build_connection!
    attempt!(event!(source), connection, status: "succeeded", duration_ms: 120)
    attempt!(event!(source), connection, status: "dead")

    get root_path
    assert_response :ok
    assert_select "canvas[data-controller=dither-chart]", count: 2
    assert_select "a[aria-current=page]", text: "24h"
    assert_match "120", response.body
    assert_match "50.0%", response.body
  end

  test "window and sort survive switching" do
    sign_in!

    get root_path(window: "7d", sort: "events")
    assert_response :ok
    assert_select "a[aria-current=page]", text: "7d"
    assert_select "nav a[href*=?]", "sort=events", count: 3
    assert_select "th a[href*=?]", "window=7d", count: 3
  end

  test "the worst connection sorts first by default" do
    sign_in!
    source_x, _dest_x, connection_x = build_connection!
    source_y, _dest_y, connection_y = build_connection!
    attempt!(event!(source_x), connection_x, status: "dead")
    attempt!(event!(source_y), connection_y, status: "succeeded")

    get root_path
    assert_response :ok
    cells = css_select("table tbody td:first-child").map(&:text)
    x = cells.index { |text| text.include?(source_x.name) }
    y = cells.index { |text| text.include?(source_y.name) }
    assert x, "expected the failing connection in the table"
    assert y, "expected the healthy connection in the table"
    assert x < y, "expected the failing connection to sort first"
  end
end
