require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  test "duplicate name in the same org is invalid case-insensitively, but valid in a different org" do
    project = create_test_project!
    project.update!(name: "Staging")

    dup = Project.new(organization: project.organization, name: "staging")
    assert_not dup.valid?
    assert_includes dup.errors[:name], "has already been taken"

    other_org_project = create_test_project!
    other_org_project.update!(name: "staging")
    assert other_org_project.valid?
  end

  test "deleting the only project in an org is blocked" do
    project = create_test_project!

    assert_equal false, project.destroy
    assert Project.exists?(project.id)
    assert_includes project.errors[:base], "The last project in an organization can't be deleted"
  end

  test "deleting one of two projects succeeds" do
    project = create_test_project!
    second = project.organization.projects.create!(name: "Second")

    assert second.destroy
    assert_not Project.exists?(second.id)
  end

  test "deleting a project nulls out memberships that remembered it" do
    project = create_test_project!
    org = project.organization
    second = org.projects.create!(name: "Second")
    membership = org.memberships.first
    membership.update!(current_project_id: second.id)

    second.destroy!

    assert_nil membership.reload.current_project_id
  end

  test "current_project_or_default returns the remembered project when accessible" do
    project = create_test_project!
    org = project.organization
    second = org.projects.create!(name: "Second")
    membership = org.memberships.first
    membership.update!(current_project_id: second.id)

    assert_equal second, membership.current_project_or_default
  end

  test "current_project_or_default falls back to the first accessible project when nil" do
    project = create_test_project!
    membership = project.organization.memberships.first
    assert_nil membership.current_project_id

    assert_equal membership.accessible_projects.first, membership.current_project_or_default
  end

  test "current_project_or_default falls back for an admin whose remembered project is gone" do
    project = create_test_project!
    membership = project.organization.memberships.first
    # ponytail: current_project_id has a real DB foreign key (on_delete: :nullify), so a
    # truly nonexistent id can't be written even via update_column. A project id from a
    # different org is real (satisfies the FK) but just as inaccessible to this membership.
    foreign_project = create_test_project!
    membership.update_column(:current_project_id, foreign_project.id)

    assert_equal membership.accessible_projects.first, membership.current_project_or_default
  end

  test "current_project_or_default falls back for a member whose grant was revoked" do
    project = create_test_project!
    org = project.organization
    second = org.projects.create!(name: "Second")
    third = org.projects.create!(name: "Third")

    member_user = User.create!(github_uid: "member-#{SecureRandom.hex(4)}", github_login: "member")
    membership = Membership.create!(organization: org, user: member_user, role: "member")
    revoked_grant = ProjectGrant.create!(membership: membership, project: second, level: "viewer")
    ProjectGrant.create!(membership: membership, project: third, level: "viewer")
    membership.update!(current_project_id: second.id)
    revoked_grant.destroy!

    assert_equal third, membership.current_project_or_default
  end

  test "destroying an organization cascades through its last project" do
    project = create_test_project!
    org = project.organization

    assert_difference -> { Project.count }, -1 do
      org.destroy!
    end
  end
end
