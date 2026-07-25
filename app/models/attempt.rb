class Attempt < ApplicationRecord
  belongs_to :event
  belongs_to :connection

  enum :status, {
    pending: "pending",
    held: "held",
    delivering: "delivering",
    succeeded: "succeeded",
    failed: "failed",
    dead: "dead"
  }

  # The retryable deliveries among `events`: the latest attempt per
  # (event, connection) pair that ended failed or dead, on a connection that
  # is currently active — paused/disabled connections don't retry.
  def self.retryable_for(events)
    latest = where(event_id: events.select(:id))
               .select("DISTINCT ON (attempts.event_id, attempts.connection_id) attempts.*")
               .order(:event_id, :connection_id, attempt_number: :desc)
    from(latest, :attempts).where(status: %w[failed dead])
      .joins(:connection).where(connections: { status: "active" })
  end

  # Claim the pair's retry slot by appending a :pending attempt — the unique
  # (event, connection, attempt_number) index arbitrates concurrent claims —
  # then enqueue delivery. False means a concurrent claim won the race.
  def self.claim_retry!(event_id:, connection_id:, replay: false)
    number = where(event_id: event_id, connection_id: connection_id).maximum(:attempt_number).to_i + 1
    create!(event_id: event_id, connection_id: connection_id, attempt_number: number,
            status: :pending, attempted_at: Time.current, replay: replay)
    DeliverEventJob.perform_later(event_id, connection_id, replay: replay)
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end

  # Event ids among `events` whose latest attempt on `connection` is still in
  # flight — replaying those would race the delivery already underway.
  def self.in_flight_event_ids(events, connection)
    latest = where(event_id: events.select(:id), connection_id: connection.id)
               .select("DISTINCT ON (attempts.event_id) attempts.*")
               .order(:event_id, attempt_number: :desc)
    from(latest, :attempts).where(status: Event::IN_FLIGHT_STATUSES).pluck(:event_id).to_set
  end
end
