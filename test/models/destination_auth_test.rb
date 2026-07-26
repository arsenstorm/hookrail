require "test_helper"

class DestinationAuthTest < ActiveSupport::TestCase
  def destination(auth)
    Destination.new(name: "D", url: "https://dest.test/hook", project: create_test_project!, auth: auth)
  end

  test "bearer without token is invalid; with token is valid" do
    without_token = destination(type: "bearer")
    assert_not without_token.valid?
    assert_includes without_token.errors[:auth_token], "can't be blank"

    with_token = destination(type: "bearer", token: "tok")
    assert with_token.valid?
  end

  test "basic without username is invalid; with username and blank password is valid" do
    without_username = destination(type: "basic")
    assert_not without_username.valid?
    assert_includes without_username.errors[:auth_username], "can't be blank"

    with_username = destination(type: "basic", username: "u")
    assert with_username.valid?
  end

  test "type none (or blank) with leftover token/username clears auth" do
    none = destination(type: "none", token: "tok", username: "u")
    assert none.valid?
    assert_equal({}, none.auth)

    blank = destination(type: "", token: "tok")
    assert blank.valid?
    assert_equal({}, blank.auth)
  end

  test "invalid auth_type is rejected" do
    invalid = destination(type: "digest")
    assert_not invalid.valid?
    assert_includes invalid.errors[:auth_type], "is not included in the list"
  end

  test "authorization_header is nil when unconfigured" do
    assert_nil destination({}).authorization_header
  end

  test "authorization_header for bearer" do
    assert_equal "Bearer tok", destination(type: "bearer", token: "tok").authorization_header
  end

  test "authorization_header for basic" do
    d = destination(type: "basic", username: "u", password: "p")
    assert_equal "Basic #{Base64.strict_encode64("u:p")}", d.authorization_header
  end

  test "authorization_header for basic with blank password" do
    d = destination(type: "basic", username: "u")
    assert_equal "Basic #{Base64.strict_encode64("u:")}", d.authorization_header
  end
end
