require "test_helper"

class ApiV1AuthTest < ActionDispatch::IntegrationTest
  def issue_key!(org)
    ApiKey.issue!(organization: org, name: "test")
  end

  def auth(raw)
    { "Authorization" => "Bearer #{raw}" }
  end

  test "no Authorization header is rejected" do
    get "/api/v1/sources"
    assert_response :unauthorized
    assert_equal "unauthorized", JSON.parse(response.body)["error"]["code"]
  end

  test "a garbage key is rejected" do
    get "/api/v1/sources", headers: auth("garbage")
    assert_response :unauthorized
    assert_equal "unauthorized", JSON.parse(response.body)["error"]["code"]
  end

  test "a revoked key is rejected" do
    org = create_test_project!.organization
    key, raw = issue_key!(org)
    key.revoke!

    get "/api/v1/sources", headers: auth(raw)
    assert_response :unauthorized
    assert_equal "unauthorized", JSON.parse(response.body)["error"]["code"]
  end

  test "a valid key is accepted" do
    org = create_test_project!.organization
    _key, raw = issue_key!(org)

    get "/api/v1/sources", headers: auth(raw)
    assert_response :ok
    assert_equal({ "sources" => [] }, JSON.parse(response.body))
  end
end
