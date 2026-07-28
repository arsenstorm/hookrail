class PruneOldRecordsJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 1000
  # How long past the retention cutoff an event may linger because one of its
  # attempts never reached a terminal state. Beyond this it is pruned anyway.
  IN_FLIGHT_GRACE = 30.days

  def perform(batch_size: BATCH_SIZE)
    stale_authorizations = CliAuthorization.where(expires_at: ...1.day.ago).delete_all
    Rails.logger.info("PruneOldRecordsJob deleted stale cli_authorizations=#{stale_authorizations}")

    Organization.find_each do |org|
      cutoff = org.retention_days.days.ago
      source_ids = Source.joins(:project).where(projects: { organization_id: org.id }).select(:id)
      events = 0
      attempts = 0
      # `held` is not a transient state: it lasts as long as its connection
      # stays paused. Skipping in-flight events forever would exempt them from
      # retention entirely, so the reprieve only holds until this grace expires.
      hard_cutoff = cutoff - IN_FLIGHT_GRACE

      loop do
        # Events with an in-flight attempt are skipped until terminal; they
        # become eligible on a later run, or at hard_cutoff regardless.
        protected_events = Attempt.where(status: Event::IN_FLIGHT_STATUSES)
                                  .where(event_id: Event.where(received_at: hard_cutoff..).select(:id))
                                  .select(:event_id)
        ids = Event.where(source_id: source_ids, received_at: ...cutoff)
                   .where.not(id: protected_events)
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
