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

  test "redirects unauthenticated users to login" do
    get root_path
    assert_redirected_to login_path
  end

  test "first sign-in creates user, org, and default project" do
    assert_difference [ "User.count", "Organization.count", "Project.count" ], 1 do
      sign_in!
    end
    assert_redirected_to root_path
    user = User.last
    assert_equal "12345", user.github_uid
    assert_equal "octocat", user.github_login
    assert_equal "Default", user.organization.projects.first.name
    # session established: a protected route now works
    get root_path
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
    delete logout_path
    assert_redirected_to login_path
    get root_path
    assert_redirected_to login_path
  end

  test "resources require a project" do
    assert_raises(ActiveRecord::RecordInvalid, ActiveRecord::NotNullViolation, ActiveRecord::StatementInvalid) do
      Source.create!(name: "No Project")
    end
  end
end
