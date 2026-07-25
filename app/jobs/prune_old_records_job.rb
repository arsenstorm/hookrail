class PruneOldRecordsJob < ApplicationJob
  queue_as :default

  RETENTION = 30.days
  BATCH_SIZE = 1000

  def perform(batch_size: BATCH_SIZE)
    cutoff = RETENTION.ago
    events = 0
    attempts = 0
    loop do
      ids = Event.where(received_at: ...cutoff).limit(batch_size).pluck(:id)
      break if ids.empty?

      # attempts.event_id has no ON DELETE CASCADE; delete children first.
      attempts += Attempt.where(event_id: ids).delete_all
      events += Event.where(id: ids).delete_all
    end
    quarantined = QuarantinedWebhook.where(received_at: ...cutoff).in_batches(of: batch_size).delete_all
    Rails.logger.info(
      "PruneOldRecordsJob deleted events=#{events} attempts=#{attempts} quarantined_webhooks=#{quarantined}"
    )
  end
end
