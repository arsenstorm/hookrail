require "test_helper"

class IssueTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # R2's concurrency test needs genuinely separate DB connections/sessions so
  # the race is real; Rails' default transactional-test connection pinning
  # would serialize the threads onto one session instead. Nothing rolls back
  # automatically without transactional tests, so track and destroy every org
  # this file creates — cascades clean up projects/sources/connections/issues,
  # and other test files rely on a clean slate for fixture loading.
  self.use_transactional_tests = false

  setup { @created_organizations = [] }

  teardown do
    Issue.delete_all
    Organization.where(id: @created_organizations.map(&:id)).destroy_all
  end

  def create_test_project!
    project = super
    @created_organizations << project.organization
    project
  end

  def build_connection!(project, url: "https://dest-#{SecureRandom.hex(3)}.test/hook")
    source      = Source.create!(project: project, name: "S-#{SecureRandom.hex(3)}")
    destination = Destination.create!(project: project, name: "D-#{SecureRandom.hex(3)}", url: url)
    Connection.create!(project: project, source: source, destination: destination)
  end

  test "record! creates an open issue with count 1" do
    project = create_test_project!
    connection = build_connection!(project)

    Issue.record!(type: :delivery_failure, subject: connection, summary: "5 consecutive delivery failures")

    issue = Issue.sole
    assert issue.status_open?
    assert_equal 1, issue.count
    assert_equal project.id, issue.project_id
    assert_equal connection, issue.subject
    assert_not_nil issue.first_seen_at
    assert_not_nil issue.last_seen_at
    assert_in_delta issue.first_seen_at, issue.last_seen_at, 1.second
  end

  test "record! again for the same type/subject increments count and does not notify again" do
    project = create_test_project!
    project.organization.update!(slack_webhook_url: "https://hooks.slack.test/T/B/x")
    connection = build_connection!(project)

    Issue.record!(type: :delivery_failure, subject: connection, summary: "5 consecutive delivery failures")
    issue = Issue.sole
    first_seen = issue.first_seen_at

    travel 1.minute do
      assert_no_enqueued_jobs only: ChatAlertJob do
        Issue.record!(type: :delivery_failure, subject: connection, summary: "5 consecutive delivery failures")
      end
    end

    assert_equal 1, Issue.count
    issue.reload
    assert_equal 2, issue.count
    assert_equal first_seen, issue.first_seen_at
    assert_operator issue.last_seen_at, :>, first_seen
  end

  test "concurrent record! calls for the same subject result in one issue with count 4" do
    project = create_test_project!
    connection = build_connection!(project)

    errors = Queue.new
    threads = 4.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Issue.record!(type: :delivery_failure, subject: connection, summary: "boom")
        end
      rescue => e
        errors << e
      end
    end
    threads.each(&:join)

    raise errors.pop unless errors.empty?

    assert_equal 1, Issue.count
    assert_equal 4, Issue.sole.count
  end

  test "bump! with no open issue is a no-op" do
    project = create_test_project!
    connection = build_connection!(project)

    Issue.bump!(type: :delivery_failure, subject: connection)

    assert_equal 0, Issue.count
  end

  test "auto_resolve! resolves the open issue; a following record! creates a new row and notifies" do
    project = create_test_project!
    project.organization.update!(slack_webhook_url: "https://hooks.slack.test/T/B/x",
                                  discord_webhook_url: "https://discord.test/api/webhooks/1/x")
    connection = build_connection!(project)

    Issue.record!(type: :delivery_failure, subject: connection, summary: "5 consecutive delivery failures")
    original = Issue.sole
    Issue.auto_resolve!(type: :delivery_failure, subject: connection)
    assert original.reload.status_resolved?

    assert_enqueued_jobs 2, only: ChatAlertJob do
      Issue.record!(type: :delivery_failure, subject: connection, summary: "5 consecutive delivery failures")
    end

    assert_equal 2, Issue.count
    new_issue = Issue.unresolved.sole
    assert_not_equal original.id, new_issue.id
    assert new_issue.status_open?
  end

  test "different type, same subject creates separate issues" do
    project = create_test_project!
    connection = build_connection!(project)

    Issue.record!(type: :delivery_failure, subject: connection, summary: "a")
    Issue.record!(type: :transformation_error, subject: connection, summary: "b")

    assert_equal 2, Issue.count
  end

  test "subject_name renders a connection as source to destination, and a source as its name" do
    project = create_test_project!
    connection = build_connection!(project)
    Issue.record!(type: :delivery_failure, subject: connection, summary: "x")
    connection_issue = Issue.sole
    assert_equal "#{connection.source.name} → #{connection.destination.name}", connection_issue.subject_name

    source = Source.create!(project: project, name: "GitHub")
    Issue.record!(type: :webhook_quarantined, subject: source, summary: "signature mismatch")
    source_issue = Issue.where(subject: source).sole
    assert_equal source.name, source_issue.subject_name
  end
end
