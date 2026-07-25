class DeliverEventJob < ApplicationJob
  queue_as :default

  BACKOFF = [ 10.seconds, 1.minute, 5.minutes, 30.minutes, 2.hours ].freeze
  MAX_ATTEMPTS = BACKOFF.size + 1 # 1 initial + 5 retries = 6

  class DeliveryError < StandardError; end

  retry_on DeliveryError,
    attempts: MAX_ATTEMPTS,
    wait: ->(executions) { BACKOFF[executions - 1] || BACKOFF.last } do |job, _error|
    event_id, connection_id = job.arguments
    Attempt.where(event_id: event_id, connection_id: connection_id)
           .order(:attempt_number).last&.update!(status: :dead)
  end

  def perform(event_id, connection_id, replay: false)
    # Idempotency (Slice 5 R4): once any delivery for this pair has succeeded, never send
    # again. Covers a manual retry racing the still-scheduled automatic retry. Replays are
    # exempt: re-delivering an already-delivered event is exactly what a replay is.
    return if !replay && Attempt.where(event_id: event_id, connection_id: connection_id).succeeded.exists?

    event = Event.find(event_id)
    connection = Connection.find(connection_id)
    attempt = claim_or_build_attempt(event, connection, replay)

    result = Delivery::Client.deliver(event: event, destination: connection.destination, replay: replay)

    if result.success?
      attempt.update!(
        status: :succeeded,
        response_status: result.status,
        response_body: result.body_excerpt,
        duration_ms: result.duration_ms
      )
      connection.record_delivery_success
    else
      attempt.update!(
        status: :failed,
        response_status: result.status,
        response_body: result.body_excerpt,
        error: result.error,
        duration_ms: result.duration_ms
      )
      connection.record_delivery_failure
      raise DeliveryError
    end
  end

  private

  # A manual retry pre-creates a :pending attempt to claim the delivery slot (Slice 5 R5).
  # Consume it if present; automatic deliveries (ingest, retry_on) have none -> build fresh.
  # ponytail: an orphaned :pending (claim created after a concurrent success) is left as-is;
  # harmless at dogfood scale, revisit if stuck-pending rows appear.
  def claim_or_build_attempt(event, connection, replay)
    pending = Attempt.where(event: event, connection: connection, status: :pending)
                     .order(:attempt_number).last
    if pending
      pending.update!(status: :delivering, attempted_at: Time.current)
      pending
    else
      Attempt.create!(
        event: event, connection: connection,
        attempt_number: next_attempt_number(event, connection),
        status: :delivering, attempted_at: Time.current, replay: replay
      )
    end
  end

  def next_attempt_number(event, connection)
    Attempt.where(event: event, connection: connection).maximum(:attempt_number).to_i + 1
  end
end
