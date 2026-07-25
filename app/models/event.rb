class Event < ApplicationRecord
  belongs_to :source
  has_many :attempts, dependent: :destroy

  # Raw wire data from arbitrary senders — scrub \0/invalid UTF-8 or the
  # ingest INSERT raises and the webhook 500s.
  normalizes :body, with: DB_TEXT
  normalizes :headers, with: ->(h) { h.transform_values { |v| DB_TEXT.call(v) } }

  # Rolled-up delivery status filter values, in UI display order.
  DELIVERY_STATUSES = %w[delivered failed partial pending undelivered duplicate].freeze

  # Attempt statuses that mean "still in flight" — no terminal outcome yet.
  # held means the connection is paused; no terminal outcome yet.
  IN_FLIGHT_STATUSES = %w[pending delivering held].freeze

  # Filter events by their rolled-up delivery status. Buckets are mutually
  # exclusive; precedence: undelivered -> pending (any in-flight attempt) ->
  # delivered (all succeeded) -> failed (all failed/dead) -> partial (mixed).
  # `delivering` is treated as in-flight so a mid-delivery event never reads as
  # failed. An unknown value returns all (caller already guards). `duplicate`
  # selects deduplicated events; `undelivered` excludes them since a duplicate
  # is intentionally undelivered, not stuck.
  scope :with_delivery_status, ->(status) {
    case status
    when "undelivered"
      where.not(id: Attempt.select(:event_id)).where(duplicate: false)
    when "duplicate"
      where(duplicate: true)
    when "pending"
      where(id: Attempt.where(status: IN_FLIGHT_STATUSES).select(:event_id))
    when "delivered"
      where(id: Attempt.select(:event_id))
        .where.not(id: Attempt.where.not(status: "succeeded").select(:event_id))
    when "failed"
      where(id: Attempt.select(:event_id))
        .where.not(id: Attempt.where(status: "succeeded").select(:event_id))
        .where.not(id: Attempt.where(status: IN_FLIGHT_STATUSES).select(:event_id))
    when "partial"
      where(id: Attempt.where(status: "succeeded").select(:event_id))
        .where(id: Attempt.where(status: %w[failed dead]).select(:event_id))
        .where.not(id: Attempt.where(status: IN_FLIGHT_STATUSES).select(:event_id))
    else
      all
    end
  }

  # Keyset pagination: rows strictly older than the cursor row, in
  # (received_at desc, id desc) order.
  scope :before_cursor, ->(received_at, id) {
    where("events.received_at < :ts OR (events.received_at = :ts AND events.id < :id)",
          ts: received_at, id: id)
  }
end
