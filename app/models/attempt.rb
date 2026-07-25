class Attempt < ApplicationRecord
  belongs_to :event
  belongs_to :connection

  enum :status, {
    pending: "pending",
    delivering: "delivering",
    succeeded: "succeeded",
    failed: "failed",
    dead: "dead"
  }

  # The retryable deliveries among `events`: the latest attempt per
  # (event, connection) pair, where that attempt ended failed or dead.
  def self.retryable_for(events)
    latest = where(event_id: events.select(:id))
               .select("DISTINCT ON (attempts.event_id, attempts.connection_id) attempts.*")
               .order(:event_id, :connection_id, attempt_number: :desc)
    from(latest, :attempts).where(status: %w[failed dead])
  end

  # Claim the pair's retry slot by appending a :pending attempt — the unique
  # (event, connection, attempt_number) index arbitrates concurrent claims —
  # then enqueue delivery. False means a concurrent claim won the race.
  def self.claim_retry!(event_id:, connection_id:)
    number = where(event_id: event_id, connection_id: connection_id).maximum(:attempt_number).to_i + 1
    create!(event_id: event_id, connection_id: connection_id, attempt_number: number,
            status: :pending, attempted_at: Time.current)
    DeliverEventJob.perform_later(event_id, connection_id)
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end
end
