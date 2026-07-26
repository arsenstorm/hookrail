class PruneOldRecordsJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 1000

  def perform(batch_size: BATCH_SIZE)
    stale_authorizations = CliAuthorization.where(expires_at: ...1.day.ago).delete_all
    Rails.logger.info("PruneOldRecordsJob deleted stale cli_authorizations=#{stale_authorizations}")

    Organization.find_each do |org|
      cutoff = org.retention_days.days.ago
      source_ids = Source.joins(:project).where(projects: { organization_id: org.id }).select(:id)
      events = 0
      attempts = 0
      loop do
        # Events with an in-flight attempt are skipped until terminal; they
        # become eligible on a later run.
        ids = Event.where(source_id: source_ids, received_at: ...cutoff)
                   .where.not(id: Attempt.where(status: Event::IN_FLIGHT_STATUSES).select(:event_id))
                   .limit(batch_size).pluck(:id)
        break if ids.empty?

        # attempts.event_id has no ON DELETE CASCADE; delete children first.
        attempts += Attempt.where(event_id: ids).delete_all
        events += Event.where(id: ids).delete_all
      end
      quarantined = QuarantinedWebhook.where(source_id: source_ids, received_at: ...cutoff)
                                      .in_batches(of: batch_size).delete_all
      Rails.logger.info(
        "PruneOldRecordsJob org=#{org.id} retention_days=#{org.retention_days} " \
        "deleted events=#{events} attempts=#{attempts} quarantined_webhooks=#{quarantined}"
      )
    end
  end
end
