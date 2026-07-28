require "test_helper"

class AuthFlowTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new(
      provider: "github",
      uid: "12345",
      info: { nickname: "octocat", name: "The Octocat", email: "octo@example.com", image: "https://avatars/1" }
    )
  end

  teardown do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:github] = nil
  end

  def sign_in!
    post "/auth/github"          # OmniAuth request phase (test mode) -> redirects to callback
    follow_redirect!            # GET /auth/github/callback -> sessions#create
  end

  test "redirects unauthenticated users to sign-in" do
    get dashboard_path
    assert_redirected_to sign_in_path
  end

  test "the sign-in page offers GitHub" do
    get sign_in_path
    assert_response :ok
    assert_select "form[action='/auth/github'] button", text: /Continue with GitHub/
  end

  test "root renders the marketing page and its CTA follows the session" do
    get root_path
    assert_response :ok
    assert_select "a[href=?]", sign_in_path, text: "Get started"
    assert_select "a[href=?]", dashboard_path, false

    sign_in!
    get root_path
    assert_response :ok
    assert_select "a[href=?]", dashboard_path, text: "Open dashboard"
    assert_select "a[href=?]", sign_in_path, false
  end

  test "the old auth paths keep working" do
    get "/login"
    assert_response :moved_permanently
    assert_redirected_to sign_in_path

    delete "/logout"
    assert_response :moved_permanently
    assert_redirected_to sign_out_path
  end

  test "first sign-in creates user, org, and default project" do
    assert_difference [ "User.count", "Organization.count", "Project.count" ], 1 do
      sign_in!
    end
    assert_redirected_to dashboard_path
    user = User.last
    assert_equal "12345", user.github_uid
    assert_equal "octocat", user.github_login
    assert_equal "Default", user.organization.projects.first.name
    # session established: a protected route now works
    get dashboard_path
    assert_response :ok
  end

  test "repeat sign-in reuses the same account" do
    sign_in!
    assert_no_difference [ "User.count", "Organization.count", "Project.count" ] do
      reset!                    # fresh session (integration test helper)
      sign_in!
    end
  end

  test "sign out clears the session" do
    sign_in!
    delete sign_out_path
    assert_redirected_to sign_in_path
    get dashboard_path
    assert_redirected_to sign_in_path
  end

  test "resources require a project" do
    assert_raises(ActiveRecord::RecordInvalid, ActiveRecord::NotNullViolation, ActiveRecord::StatementInvalid) do
      Source.create!(name: "No Project")
    end
  end
end
