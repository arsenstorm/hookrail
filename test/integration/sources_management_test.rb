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

  test "an empty index keeps the table header and puts the empty state in a row" do
    sign_in!

    get sources_path
    assert_response :ok
    assert_select "table thead th", text: "Ingest URL"
    assert_select "table tbody td[colspan=4]", text: /No sources yet/
    assert_select "table tbody a[href=?]", new_source_path, text: "New source"
  end

  test "creates a source" do
    sign_in!
    assert_difference -> { current_project.sources.count }, 1 do
      post sources_path, params: { source: { name: "GitHub" } }
    end
    assert_redirected_to source_path(current_project.sources.order(:created_at).last)
  end

  test "new shows the provider picker" do
    sign_in!
    get new_source_path
    assert_response :ok
    assert_match new_source_path(provider: "stripe"), response.body
    assert_match new_source_path(provider: "github"), response.body
    assert_match "Or continue manually", response.body
    assert_no_match(/name="source\[verification_header\]"/, response.body)
  end

  test "new with a preset provider prefills it and asks only for the secret" do
    sign_in!
    get new_source_path(provider: "github")
    assert_response :ok
    assert_match(/name="source\[verification_secret\]"/, response.body)
    assert_match(/type="hidden" value="github" name="source\[verification_provider\]"/, response.body)
    assert_match(/value="GitHub" name="source\[name\]"/, response.body)
    assert_no_match(/name="source\[verification_header\]"/, response.body)
  end

  test "new with an unknown provider falls back to the picker" do
    sign_in!
    get new_source_path(provider: "bogus")
    assert_response :ok
    assert_match "Or continue manually", response.body
    assert_no_match(/name="source\[verification_secret\]"/, response.body)
  end

  test "new with manual shows the full generic form" do
    sign_in!
    get new_source_path(manual: 1)
    assert_response :ok
    assert_match(/name="source\[verification_header\]"/, response.body)
    assert_match(/name="source\[verification_payload_template\]"/, response.body)
  end

  test "new with manual collapses the advanced disclosures" do
    sign_in!
    get new_source_path(manual: 1)
    assert_match "Advanced verification", response.body
    assert_no_match(/<details[^>]*\sopen/, response.body)
  end

  test "preset phase keeps the dedupe fields inside a collapsed disclosure" do
    sign_in!
    get new_source_path(provider: "github")
    assert_match(/name="source\[dedupe_window\]"/, response.body)
    assert_no_match(/<details[^>]*\sopen/, response.body)
  end

  test "an invalid advanced field reopens its disclosure" do
    sign_in!
    post sources_path, params: { source: { name: "Custom", verification_secret: "s3cret" } }
    assert_response :unprocessable_entity
    assert_match "Verification header can&#39;t be blank", response.body
    assert_match(/<details class="group" open/, response.body)
  end

  test "edit opens the advanced disclosure when dedupe is configured" do
    sign_in!
    source = current_project.sources.create!(name: "GH", dedupe: { "window" => 120 })
    get edit_source_path(source)
    assert_match(/<details class="group" open/, response.body)
  end

  test "the blank secret warning dialog ships with the form" do
    sign_in!
    get new_source_path(manual: 1)
    assert_match "confirm-blank-secret", response.body
    assert_match "No signing secret", response.body
    assert_match(/data-confirm-blank-secret-target="secret"/, response.body)
    assert_match(/data-confirm-blank-secret-target="dialog"/, response.body)
  end

  test "creates a source from a preset provider" do
    sign_in!
    post sources_path, params: { source: { name: "Shopify", verification_provider: "shopify", verification_secret: "shpss_x" } }
    source = current_project.sources.order(:created_at).last
    assert_redirected_to source_path(source)
    assert_equal "X-Shopify-Hmac-Sha256", source.verification_header
    assert_equal "base64", source.verification_encoding
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
    assert_redirected_to sign_in_path
  end
end
