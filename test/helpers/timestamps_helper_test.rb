require "test_helper"

class TimestampsHelperTest < ActionView::TestCase
  # Fixed instant so "current year" and "prior year" are decided by the test,
  # not by whenever it runs.
  NOW = Time.utc(2025, 5, 30, 14, 23, 5)

  def assert_text(expected, time)
    travel_to(NOW) { assert_equal expected, timestamp_text(time) }
  end

  test "under a second reads as just now" do
    assert_text "Just now", NOW
    assert_text "Just now", NOW - 0.9
  end

  test "seconds" do
    assert_text "1s ago", NOW - 1
    assert_text "42s ago", NOW - 42
    assert_text "59s ago", NOW - 59
  end

  test "minutes" do
    assert_text "1m ago", NOW - 60
    assert_text "1m ago", NOW - 119
    assert_text "59m ago", NOW - 59.minutes
  end

  test "hours" do
    assert_text "1h ago", NOW - 1.hour
    assert_text "23h ago", NOW - 23.hours - 59.minutes
  end

  test "a day or more becomes a date, without the year inside this year" do
    assert_text "May 29", NOW - 24.hours
    assert_text "Jan 1", Time.utc(2025, 1, 1, 0, 0, 0)
  end

  test "a date in an earlier year carries the year" do
    assert_text "Dec 12, 2024", Time.utc(2024, 12, 12, 9, 0, 0)
  end

  test "a future time clamps to just now rather than counting backwards" do
    assert_text "Just now", NOW + 5.minutes
  end

  test "the tag carries the ISO UTC instant and the server-computed fallback" do
    travel_to(NOW) do
      html = Nokogiri::HTML5.fragment(timestamp_tag(NOW - 42))
      tag = html.at("time")
      assert_equal "2025-05-30T14:22:23Z", tag["datetime"]
      assert_equal "42s ago", tag.text
      assert_equal "0", tag["tabindex"]
      assert_equal "timestamp", tag["data-controller"]
      assert_includes tag["class"], "tabular-nums"
      assert_includes tag["class"], "whitespace-nowrap"
    end
  end

  test "tabindex can be dropped for a tag nested in a link" do
    tag = Nokogiri::HTML5.fragment(timestamp_tag(NOW, tabindex: nil)).at("time")
    assert_nil tag["tabindex"]
  end
end
