require "test_helper"

class TeamRbacFlowTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
  end

  teardown do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:github] = nil
  end

  def sign_in_as!(user)
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new(
      provider: "github", uid: user.github_uid,
      info: { nickname: user.github_login, name: user.name, email: user.email, image: nil }
    )
    post "/auth/github"
    follow_redirect!
  end

  def make_user!(login)
    user = User.create!(github_uid: "uid-#{login}", github_login: login, email: "#{login}@example.com")
    user.ensure_org_and_project!
    user
  end

  def build_connection!(project, source, destination)
    project.connections.create!(source: source, destination: destination)
  end

  def create_event!(source)
    source.events.create!(http_method: "POST", path: "/wh", received_at: Time.current, headers: {}, body: "{}")
  end

  def create_attempt!(event, connection, status:)
    Attempt.create!(event: event, connection: connection, attempt_number: 1, status: status, attempted_at: Time.current)
  end

  test "exactly one owner per org and ownership transfers atomically" do
    owner1 = make_user!("owner1")
    org = owner1.organization
    owner_membership = org.memberships.find_by(user: owner1)
    assert_equal "owner", owner_membership.role

    assert_raises(ActiveRecord::RecordNotUnique) do
      Membership.create!(organization: org, user: make_user!("x"), role: "owner")
    end

    bob = make_user!("bob")
    bob_membership = Membership.create!(organization: org, user: bob, role: "admin")

    owner_membership.transfer_ownership!(bob_membership)

    assert_equal "owner", bob_membership.reload.role
    assert_equal "admin", owner_membership.reload.role
    assert_equal bob.id, org.reload.owner_id
  end

  test "viewers read but cannot mutate, and org settings stay closed" do
    alice = make_user!("alice")
    alice_org = alice.organization
    alice_project = alice_org.projects.first
    source = alice_project.sources.create!(name: "GH-Source")
    destination = alice_project.destinations.create!(name: "API-Dest", url: "https://dest.test/hook")
    connection = build_connection!(alice_project, source, destination)
    event = create_event!(source)
    create_attempt!(event, connection, status: "dead")

    # ponytail: plain User.create! (no ensure_org_and_project!) so the team
    # membership below is carol's only one and sign-in resolves to it.
    carol = User.create!(github_uid: "uid-carol", github_login: "carol", email: "carol@example.com")
    carol_membership = Membership.create!(organization: alice_org, user: carol, role: "member")
    ProjectGrant.create!(membership: carol_membership, project: alice_project, level: "viewer")

    sign_in_as!(carol)

    get events_path
    assert_response :ok
    assert_match source.name, response.body

    get dashboard_path
    assert_response :ok

    post event_retries_path(event), params: { connection_id: connection.id }
    assert_response :see_other
    assert_redirected_to dashboard_path

    assert_no_difference "Source.count" do
      post sources_path, params: { source: { name: "New Source" } }
    end
    assert_redirected_to dashboard_path

    delete destination_path(destination)
    assert_redirected_to dashboard_path
    assert Destination.exists?(destination.id)

    get api_keys_path
    assert_redirected_to dashboard_path

    get retention_path
    assert_redirected_to dashboard_path
  end

  test "editors mutate within the project" do
    alice = make_user!("alice")
    alice_org = alice.organization
    alice_project = alice_org.projects.first
    source = alice_project.sources.create!(name: "GH-Source")
    destination = alice_project.destinations.create!(name: "API-Dest", url: "https://dest.test/hook")
    connection = build_connection!(alice_project, source, destination)
    event = create_event!(source)
    create_attempt!(event, connection, status: "dead")

    dave = User.create!(github_uid: "uid-dave", github_login: "dave", email: "dave@example.com")
    dave_membership = Membership.create!(organization: alice_org, user: dave, role: "member")
    ProjectGrant.create!(membership: dave_membership, project: alice_project, level: "editor")

    sign_in_as!(dave)

    assert_difference "Source.count", 1 do
      post sources_path, params: { source: { name: "New S" } }
    end
    new_source = Source.find_by(name: "New S")
    assert_redirected_to source_path(new_source)

    assert_difference "Attempt.count", 1 do
      post event_retries_path(event), params: { connection_id: connection.id }
    end
  end

  test "a member with no grant cannot see the project exists" do
    alice = make_user!("alice")
    alice_org = alice.organization
    alice_project = alice_org.projects.first
    source = alice_project.sources.create!(name: "Secret-Source")

    erin = User.create!(github_uid: "uid-erin", github_login: "erin", email: "erin@example.com")
    Membership.create!(organization: alice_org, user: erin, role: "member")

    sign_in_as!(erin)

    get dashboard_path
    assert_response :ok
    assert_no_match source.name, response.body
    assert_no_match alice_project.name, response.body

    get events_path
    assert_redirected_to dashboard_path
  end

  test "alerts reach every owner and admin" do
    owner = make_user!("owner5")
    org = owner.organization
    project = org.projects.first
    source = project.sources.create!(name: "S")
    destination = project.destinations.create!(name: "D", url: "https://dest.test/hook")
    connection = build_connection!(project, source, destination)

    admin1 = User.create!(github_uid: "uid-admin1", github_login: "admin1", email: "admin1@example.com")
    Membership.create!(organization: org, user: admin1, role: "admin")

    admin2 = User.create!(github_uid: "uid-admin2", github_login: "admin2", email: "admin2@example.com")
    admin2.update_column(:email, "")
    Membership.create!(organization: org, user: admin2, role: "admin")

    member = User.create!(github_uid: "uid-member5", github_login: "member5", email: "member5@example.com")
    Membership.create!(organization: org, user: member, role: "member")

    expected = [ owner.email, admin1.email ].sort
    assert_equal expected, org.alert_recipients.sort

    connection.update!(unhealthy_since: 2.hours.ago, consecutive_failures: 5)
    mail = AlertMailer.connection_unhealthy(connection)
    assert_equal expected, mail.to.sort
  end

  test "existing single-user orgs behave unchanged" do
    solo = make_user!("solo")
    solo.ensure_org_and_project!

    assert_equal 1, solo.memberships.count
    assert_equal "owner", solo.memberships.first.role

    sign_in_as!(solo)

    get dashboard_path
    assert_response :ok

    get events_path
    assert_response :ok

    assert_difference "Source.count", 1 do
      post sources_path, params: { source: { name: "Solo Source" } }
    end
  end

  def sign_in_new!(login, email)
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new(
      provider: "github", uid: "uid-#{login}",
      info: { nickname: login, name: login, email: email, image: nil }
    )
    post "/auth/github"
    follow_redirect! # OmniAuth request phase → callback, which lands the session
    User.find_by(github_uid: "uid-#{login}")
  end

  test "an invitation joins the matching account and rejects others" do
    alice = make_user!("alice")
    project = alice.organization.projects.first
    invitation = alice.organization.invitations.create!(
      email: "newbie@example.com", role: "member",
      grants: [ { "project_id" => project.id, "level" => "viewer" } ]
    )

    get invite_path(invitation.token)
    assert_redirected_to sign_in_path

    # Signing in lands on the confirmation screen. Nothing is joined until the
    # POST, so following a link alone cannot move someone into another org.
    newbie = sign_in_new!("newbie", "newbie@example.com")
    assert_redirected_to invite_path(invitation.token)
    assert_nil alice.organization.memberships.find_by(user: newbie),
      "signing in must not accept the invitation by itself"

    post invite_path(invitation.token)
    membership = alice.organization.memberships.find_by(user: newbie)
    assert membership, "expected the invitation to create a membership in alice's org"
    assert_equal "member", membership.role
    assert_equal "viewer", membership.project_grants.find_by(project: project)&.level
    assert_not Invitation.exists?(invitation.id), "accepting should consume the invitation"

    follow_redirect!
    assert_response :ok
    assert_match alice.organization.name, response.body

    other = alice.organization.invitations.create!(email: "someoneelse@example.com", role: "member")
    reset!
    get invite_path(other.token)
    assert_redirected_to sign_in_path

    wrong = sign_in_new!("wrong", "wrong@example.com")
    post invite_path(other.token)
    assert_nil alice.organization.memberships.find_by(user: wrong)
    assert Invitation.exists?(other.id), "a mismatched email must leave the invitation pending"
  end

  test "expired invitations grant nothing" do
    alice = make_user!("alice")
    invitation = alice.organization.invitations.create!(email: "late@example.com", role: "member")
    invitation.update_column(:created_at, 8.days.ago)

    get invite_path(invitation.token)
    assert_redirected_to sign_in_path

    late = sign_in_new!("late", "late@example.com")
    post invite_path(invitation.token)
    assert_nil alice.organization.memberships.find_by(user: late)

    follow_redirect!
    assert_match "expired", response.body
  end
end
