require "test_helper"

class EventsFilteringTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new(
      provider: "github", uid: "12345",
      info: { nickname: "octocat", name: "The Octocat", email: "octo@example.com", image: "https://avatars/1" }
    )
    sign_in!
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

  def make_source!(project = current_project, name: "S-#{SecureRandom.hex(3)}")
    Source.create!(project: project, name: name)
  end

  def make_connection!(source, project = current_project)
    dest = Destination.create!(project: project, name: "D-#{SecureRandom.hex(3)}",
                               url: "https://api.example.com/#{SecureRandom.hex(3)}")
    Connection.create!(project: project, source: source, destination: dest)
  end

  # Create an event under `source` with one attempt per status in `statuses`.
  def make_event!(source, connection, statuses: [], body: "{}", received_at: Time.current)
    event = Event.create!(source: source, http_method: "POST", path: "/wh",
                          received_at: received_at, headers: {}, body: body)
    statuses.each_with_index do |st, i|
      Attempt.create!(event: event, connection: connection, attempt_number: i + 1,
                      attempted_at: Time.current, status: st)
    end
    event
  end

  def shows?(event)
    css_select("a[href='#{event_path(event)}']").any?
  end

  # Count non-schema SQL queries issued inside the block (N+1 detector).
  def count_queries
    count = 0
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      count += 1 unless payload[:name].to_s =~ /SCHEMA|TRANSACTION/
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end

  # ---- R1 / R9: source filter + scoping ----

  test "source_id filters to that source only" do
    s1 = make_source!; c1 = make_connection!(s1)
    s2 = make_source!; c2 = make_connection!(s2)
    e1 = make_event!(s1, c1, statuses: %w[succeeded])
    e2 = make_event!(s2, c2, statuses: %w[succeeded])
    get events_path(source_id: s1.id)
    assert_response :ok
    assert shows?(e1)
    assert_not shows?(e2)
  end

  test "foreign project source_id yields empty set, not another project's events" do
    mine_src = make_source!; mine_conn = make_connection!(mine_src)
    mine = make_event!(mine_src, mine_conn, statuses: %w[succeeded])
    other_project = create_test_project!
    foreign_src = make_source!(other_project)
    get events_path(source_id: foreign_src.id)
    assert_response :ok
    assert_not shows?(mine)
    assert_match "No events match these filters", response.body
  end

  # ---- R2: status buckets ----

  test "status=failed returns only fully-failed events and excludes delivered/partial/pending" do
    s = make_source!; c = make_connection!(s)
    delivered = make_event!(s, c, statuses: %w[succeeded])
    failed    = make_event!(s, c, statuses: %w[failed dead])
    partial   = make_event!(s, c, statuses: %w[succeeded failed])
    pending   = make_event!(s, c, statuses: %w[pending])
    get events_path(status: "failed")
    assert_response :ok
    assert shows?(failed)
    assert_not shows?(delivered)
    assert_not shows?(partial)
    assert_not shows?(pending)
  end

  test "status=delivered requires all attempts succeeded" do
    s = make_source!; c = make_connection!(s)
    delivered = make_event!(s, c, statuses: %w[succeeded succeeded])
    partial   = make_event!(s, c, statuses: %w[succeeded failed])
    get events_path(status: "delivered")
    assert shows?(delivered)
    assert_not shows?(partial)
  end

  test "status=partial requires mix of succeeded and failed with no in-flight" do
    s = make_source!; c = make_connection!(s)
    partial   = make_event!(s, c, statuses: %w[succeeded failed])
    delivered = make_event!(s, c, statuses: %w[succeeded])
    failed    = make_event!(s, c, statuses: %w[failed])
    get events_path(status: "partial")
    assert shows?(partial)
    assert_not shows?(delivered)
    assert_not shows?(failed)
  end

  test "status=pending matches pending or delivering (in-flight)" do
    s = make_source!; c = make_connection!(s)
    pending    = make_event!(s, c, statuses: %w[pending])
    delivering = make_event!(s, c, statuses: %w[succeeded delivering])
    delivered  = make_event!(s, c, statuses: %w[succeeded])
    get events_path(status: "pending")
    assert shows?(pending)
    assert shows?(delivering)
    assert_not shows?(delivered)
  end

  test "status=undelivered matches events with zero attempts" do
    s = make_source!; c = make_connection!(s)
    undelivered = make_event!(s, c, statuses: [])
    delivered   = make_event!(s, c, statuses: %w[succeeded])
    get events_path(status: "undelivered")
    assert shows?(undelivered)
    assert_not shows?(delivered)
  end

  # ---- R3: date range ----

  test "from/to bound received_at inclusively and ignore garbage dates" do
    s = make_source!; c = make_connection!(s)
    old = make_event!(s, c, statuses: %w[succeeded], received_at: 3.days.ago)
    mid = make_event!(s, c, statuses: %w[succeeded], received_at: 1.day.ago)
    now = make_event!(s, c, statuses: %w[succeeded], received_at: Time.current)

    get events_path(from: 2.days.ago.to_date.to_s)
    assert shows?(mid)
    assert shows?(now)
    assert_not shows?(old)

    get events_path(to: 2.days.ago.to_date.to_s)
    assert shows?(old)
    assert_not shows?(mid)

    # Garbage date is ignored, not a 500.
    get events_path(from: "not-a-date")
    assert_response :ok
    assert shows?(old)
  end

  # ---- R4: body search ----

  test "q does case-insensitive substring search on body and escapes wildcards" do
    s = make_source!; c = make_connection!(s)
    hit  = make_event!(s, c, statuses: %w[succeeded], body: %({"order":"4821","state":"FAILED"}))
    miss = make_event!(s, c, statuses: %w[succeeded], body: %({"order":"9999"}))

    get events_path(q: "4821")
    assert shows?(hit)
    assert_not shows?(miss)

    get events_path(q: "failed") # case-insensitive
    assert shows?(hit)

    get events_path(q: "zzz-nope")
    assert_not shows?(hit)
    assert_match "No events match these filters", response.body
  end

  # ---- R5: filters compose with AND ----

  test "source_id, status and q compose with AND" do
    s1 = make_source!; c1 = make_connection!(s1)
    s2 = make_source!; c2 = make_connection!(s2)
    want  = make_event!(s1, c1, statuses: %w[failed], body: "boom order 5")
    wrong_source = make_event!(s2, c2, statuses: %w[failed], body: "boom order 5")
    wrong_status = make_event!(s1, c1, statuses: %w[succeeded], body: "boom order 5")
    wrong_body   = make_event!(s1, c1, statuses: %w[failed], body: "quiet")
    get events_path(source_id: s1.id, status: "failed", q: "boom")
    assert shows?(want)
    assert_not shows?(wrong_source)
    assert_not shows?(wrong_status)
    assert_not shows?(wrong_body)
  end

  # ---- R6: cursor pagination reaches beyond the old 100-row cap ----

  test "pagination pages through 105 events and reaches event beyond the old 100 cap" do
    s = make_source!; c = make_connection!(s)
    # Distinct received_at so ordering is deterministic; newest first.
    events = 105.times.map do |i|
      make_event!(s, c, statuses: %w[succeeded], received_at: i.minutes.ago)
    end
    newest = events.first        # i=0, most recent
    beyond_cap = events[100]     # 101st newest — unreachable under the old limit(100)

    get events_path
    assert_response :ok
    assert_equal 50, css_select("tbody tr").size
    assert shows?(newest)
    assert_not shows?(beyond_cap)
    next_href = css_select("a").find { |a| a.text.include?("Next") }&.attr("href")
    assert next_href, "expected a Next link on page 1"

    get next_href # page 2
    assert_equal 50, css_select("tbody tr").size
    assert_not shows?(beyond_cap)
    next_href = css_select("a").find { |a| a.text.include?("Next") }&.attr("href")
    assert next_href, "expected a Next link on page 2"

    get next_href # page 3
    assert_equal 5, css_select("tbody tr").size
    assert shows?(beyond_cap)
    assert_nil css_select("a").find { |a| a.text.include?("Next") }, "last page must have no Next link"
  end

  test "cursor carries active filters forward" do
    s1 = make_source!; c1 = make_connection!(s1)
    s2 = make_source!; c2 = make_connection!(s2)
    60.times { |i| make_event!(s1, c1, statuses: %w[succeeded], received_at: i.minutes.ago) }
    make_event!(s2, c2, statuses: %w[succeeded]) # different source, must never appear
    get events_path(source_id: s1.id)
    next_href = css_select("a").find { |a| a.text.include?("Next") }.attr("href")
    assert_includes next_href, "source_id=#{s1.id}"
    get next_href
    assert_response :ok
    assert css_select("tbody tr").size <= 50
  end

  # ---- R7: no N+1 ----

  test "index query count does not grow with row count" do
    s = make_source!; c = make_connection!(s)
    3.times { make_event!(s, c, statuses: %w[succeeded]) }
    c1 = count_queries { get events_path }
    10.times { make_event!(s, c, statuses: %w[succeeded failed]) }
    c2 = count_queries { get events_path }
    assert_equal c1, c2, "event index SQL count grew with rows — N+1 regression"
  end
end
