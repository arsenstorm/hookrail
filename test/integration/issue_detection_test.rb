require "test_helper"

class IssueDetectionTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "delivery_failure: 5 consecutive failures open an issue; a success resolves it" do
    project = create_test_project!
    source = Source.create!(project: project, name: "S1")
    destination = Destination.create!(project: project, name: "D1", url: "https://dest.test/hook")
    connection = Connection.create!(project: project, source: source, destination: destination)

    5.times { connection.record_delivery_failure }

    issue = Issue.where(subject: connection, issue_type: "delivery_failure").sole
    assert issue.status_open?
    assert_equal "5 consecutive delivery failures", issue.summary

    connection.record_delivery_success

    assert issue.reload.status_resolved?
  end

  test "transformation_error: a throwing transform opens an issue on the connection" do
    project = create_test_project!
    source = Source.create!(project: project, name: "S2")
    destination = Destination.create!(project: project, name: "D2", url: "https://dest2.test/hook")
    connection = Connection.create!(
      project: project, source: source, destination: destination,
      transformation: "function transform(request) { throw new Error('nope'); }"
    )
    stub_request(:post, destination.url).to_return(status: 200)

    perform_enqueued_jobs do
      post "/ingest/#{source.token}", params: '{"a":1}', headers: { "Content-Type" => "application/json" }
    end

    issue = Issue.where(subject: connection, issue_type: "transformation_error").sole
    assert issue.status_open?
  end

  test "webhook_quarantined: a bad-signature request opens an issue on the source" do
    project = create_test_project!
    source = Source.create!(
      project: project, name: "S3",
      verification: {
        secret: "testsecret", header: "X-Hub-Signature-256",
        header_format: "value", signature_prefix: "sha256="
      }
    )

    post "/ingest/#{source.token}", params: '{"hello":"world"}', headers: {
      "Content-Type" => "application/json",
      "X-Hub-Signature-256" => "sha256=deadbeef"
    }
    assert_response :unauthorized

    webhook = source.quarantined_webhooks.last
    issue = Issue.where(subject: source, issue_type: "webhook_quarantined").sole
    assert issue.status_open?
    assert_equal webhook.reason, issue.summary
  end
end
