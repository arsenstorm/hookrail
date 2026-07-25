require "test_helper"

class ConnectionHealthTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @project = create_test_project!
    @project.organization.owner.update!(email: "owner@example.com")
    @source = Source.create!(project: @project, name: "GitHub")
    destination = Destination.create!(project: @project, name: "API", url: "https://dest.test/hook")
    @connection = Connection.create!(project: @project, source: @source, destination: destination)
  end

  test "five consecutive failures flip the connection to unhealthy with one email" do
    assert_enqueued_emails 1 do
      5.times { @connection.record_delivery_failure }
    end

    @connection.reload
    assert @connection.unhealthy?
    assert_equal 5, @connection.consecutive_failures
  end

  test "further failures while unhealthy send no additional email" do
    5.times { @connection.record_delivery_failure }

    assert_no_enqueued_emails do
      @connection.record_delivery_failure
    end

    assert @connection.reload.unhealthy?
  end

  test "a success resets the counter before the threshold" do
    assert_no_enqueued_emails do
      4.times { @connection.record_delivery_failure }
      @connection.record_delivery_success
    end

    @connection.reload
    assert_not @connection.unhealthy?
    assert_equal 0, @connection.consecutive_failures
  end

  test "a success after unhealthy recovers with one email" do
    5.times { @connection.record_delivery_failure }

    assert_enqueued_emails(1) { @connection.record_delivery_success }

    @connection.reload
    assert_nil @connection.unhealthy_since
    assert_equal 0, @connection.consecutive_failures
  end

  test "creating a quarantined webhook enqueues an alert email" do
    assert_enqueued_emails(1) do
      @source.quarantined_webhooks.create!(
        http_method: "POST", headers: {}, reason: "signature mismatch", received_at: Time.current
      )
    end
  end

  test "no email is enqueued when the org owner has no email" do
    @project.organization.owner.update!(email: nil)

    assert_no_emails do
      5.times { @connection.record_delivery_failure }
    end

    assert @connection.reload.unhealthy?
  end
end
