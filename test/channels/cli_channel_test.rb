require "test_helper"

class CliChannelTest < ActionCable::Channel::TestCase
  def make_org_user!(login)
    user = User.create!(github_uid: "uid-#{login}", github_login: login, email: "#{login}@example.com")
    user.ensure_org_and_project!
    user
  end

  def build_cli_connection!(project)
    source = project.sources.create!(name: "Src")
    destination = project.destinations.create!(name: "CLI dest", kind: :cli)
    project.connections.create!(source: source, destination: destination)
  end

  def build_http_connection!(project)
    source = project.sources.create!(name: "Src")
    destination = project.destinations.create!(name: "HTTP dest", url: "https://dest.test/hook")
    project.connections.create!(source: source, destination: destination)
  end

  setup do
    @user = make_org_user!("chan-owner")
    @project = @user.organization.projects.first
    @token, = CliToken.issue!(user: @user, organization: @user.organization, name: "box")
    @cli_connection = build_cli_connection!(@project)
  end

  test "subscribing with a valid cli connection id streams and marks presence online" do
    stub_connection(cli_token: @token)
    subscribe(connection_id: @cli_connection.id)

    assert subscription.confirmed?
    assert_has_stream "cli_connection_#{@cli_connection.id}"
    assert CliPresence.online?(@cli_connection.id)
  end

  test "subscribing to another org's connection id is rejected" do
    other_user = make_org_user!("chan-other")
    other_connection = build_cli_connection!(other_user.organization.projects.first)

    stub_connection(cli_token: @token)
    subscribe(connection_id: other_connection.id)

    assert subscription.rejected?
    assert_not CliPresence.online?(other_connection.id)
  end

  test "subscribing to a connection whose destination is kind http is rejected" do
    http_connection = build_http_connection!(@project)

    stub_connection(cli_token: @token)
    subscribe(connection_id: http_connection.id)

    assert subscription.rejected?
  end

  test "a plain member with no project grant is rejected even inside their own org" do
    other_user = User.create!(github_uid: "uid-chan-member", github_login: "chan-member",
                              email: "chan-member@example.com")
    Membership.create!(organization: @user.organization, user: other_user, role: "member")
    other_token, = CliToken.issue!(user: other_user, organization: @user.organization, name: "box2")

    stub_connection(cli_token: other_token)
    subscribe(connection_id: @cli_connection.id)

    assert subscription.rejected?
    assert_not CliPresence.online?(@cli_connection.id)
  end

  test "unsubscribing clears presence" do
    stub_connection(cli_token: @token)
    subscribe(connection_id: @cli_connection.id)
    assert CliPresence.online?(@cli_connection.id)

    unsubscribe
    assert_not CliPresence.online?(@cli_connection.id)
  end
end
