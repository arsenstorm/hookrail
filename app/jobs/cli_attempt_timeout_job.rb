# Fails a CLI-bound attempt whose `hookrail listen` session never reported a
# result. The guarded UPDATE races the result endpoint; whoever claims the
# delivering -> failed flip finalizes, and the loser no-ops.
class CliAttemptTimeoutJob < ApplicationJob
  queue_as :default

  TIMEOUT = 30.seconds

  def perform(attempt_id, retry_count)
    attempt = Attempt.find_by(id: attempt_id)
    return unless attempt&.delivering?

    claimed = Attempt.where(id: attempt.id, status: "delivering")
                     .update_all(status: "failed",
                                 error: "CLI session did not respond within #{TIMEOUT.to_i} seconds",
                                 updated_at: Time.current)
    return unless claimed == 1

    attempt.reload
    attempt.connection.record_delivery_failure
    DeliverEventJob.retry_or_bury(attempt.event, attempt.connection, attempt.replay, retry_count)
  end
end
