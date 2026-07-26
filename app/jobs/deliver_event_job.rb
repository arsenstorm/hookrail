class DeliverEventJob < ApplicationJob
  queue_as :default

  BACKOFF = [ 10.seconds, 1.minute, 5.minutes, 30.minutes, 2.hours ].freeze
  MAX_ATTEMPTS = BACKOFF.size + 1 # 1 initial + 5 retries = 6

  class DeliveryError < StandardError; end

  # Retries are scheduled by hand instead of retry_on so each connection's
  # retry_policy can shape its own schedule; retry_count rides along as a job
  # argument because a re-enqueue resets ActiveJob's executions counter.
  def perform(event_id, connection_id, replay: false, retry_count: 0)
    # Idempotency (Slice 5 R4): once any delivery for this pair has succeeded, never send
    # again. Covers a manual retry racing the still-scheduled automatic retry. Replays are
    # exempt: re-delivering an already-delivered event is exactly what a replay is.
    return if !replay && Attempt.where(event_id: event_id, connection_id: connection_id).succeeded.exists?

    event = Event.find(event_id)
    connection = Connection.find(connection_id)

    unless connection.status_active?
      hold_or_drop(event, connection, replay)
      return
    end

    wait = connection.destination.claim_delivery_slot!
    if wait.positive?
      # Rate-limited, not failed: requeue untouched — no attempt row, no
      # counters, no retry budget consumed.
      self.class.set(wait: wait).perform_later(event_id, connection_id, replay: replay, retry_count: retry_count)
      return
    end

    attempt = claim_or_build_attempt(event, connection, replay)

    transformed = nil
    if connection.transformation.present?
      begin
        transformed = Transformation::Runner.run(connection.transformation, event)
      rescue Transformation::Error => e
        # A broken transform is a failed delivery: nothing is sent, and it
        # feeds the same retry/backoff and health alerting as an HTTP error.
        attempt.update!(status: :failed, error: "TransformationError: #{e.message}")
        connection.record_delivery_failure
        Issue.record!(type: :transformation_error, subject: connection,
                      summary: "TransformationError: #{e.message}".truncate(200))
        raise DeliveryError
      end
      # Persisted by the status update below — what the transform produced,
      # for per-delivery debugging.
      attempt.assign_attributes(transformed_headers: transformed[:headers],
                                transformed_body: transformed[:body])
    end

    if connection.destination.kind_cli?
      deliver_via_cli(attempt, event, connection, replay, retry_count, transformed)
      return
    end

    result = Delivery::Client.deliver(event: event, destination: connection.destination,
                                      replay: replay, transformed: transformed)

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
  rescue DeliveryError
    self.class.retry_or_bury(event, connection, replay, retry_count)
  rescue ActiveRecord::RecordNotFound
    raise
  rescue StandardError => e
    # Retries are chained by hand (see class comment), so an unrescued crash
    # here would strand the attempt at "delivering" forever and sever the
    # chain. Convert any crash into a normal failed delivery.
    raise unless event && connection
    if attempt&.delivering?
      attempt.update!(status: :failed, error: "#{e.class}: #{e.message}")
      connection.record_delivery_failure
    end
    self.class.retry_or_bury(event, connection, replay, retry_count)
  end

  # Also called by the CLI tunnel finalizers (result endpoint, timeout job),
  # which learn the outcome long after the delivering job has exited.
  def self.retry_or_bury(event, connection, replay, retry_count)
    retries_done = retry_count + 1
    if retries_done < max_attempts_for(connection)
      set(wait: wait_for(connection, retries_done))
        .perform_later(event.id, connection.id, replay: replay, retry_count: retries_done)
    else
      Attempt.where(event_id: event.id, connection_id: connection.id)
             .order(:attempt_number).last&.update!(status: :dead)
    end
  end

  def self.max_attempts_for(connection)
    connection.retry_policy.present? ? connection.retry_policy["max_attempts"] : MAX_ATTEMPTS
  end

  # Wait before attempt retries_done + 1: linear repeats the interval,
  # exponential doubles it each retry starting from the interval.
  def self.wait_for(connection, retries_done)
    policy = connection.retry_policy
    if policy.present?
      interval = policy["interval"].seconds
      policy["strategy"] == "exponential" ? interval * (2**(retries_done - 1)) : interval
    else
      BACKOFF[retries_done - 1] || BACKOFF.last
    end
  end

  private

  # CLI-bound deliveries hand off to a live `hookrail listen` session over
  # Action Cable and finish later: the CLI posts the outcome back, or
  # CliAttemptTimeoutJob fails the attempt. No live session = an ordinary
  # failure that re-enters the retry chain.
  def deliver_via_cli(attempt, event, connection, replay, retry_count, transformed)
    unless CliPresence.online?(connection.id)
      attempt.update!(status: :failed, error: "No CLI session is listening")
      connection.record_delivery_failure
      raise DeliveryError
    end

    payload = Delivery::Client.payload_for(event: event, destination: connection.destination,
                                           replay: replay, transformed: transformed)
    attempt.save! # persist transformed_headers/body assigned above while the result is pending
    ActionCable.server.broadcast("cli_connection_#{connection.id}",
                                 { attempt_id: attempt.id, retry_count: retry_count,
                                   event_id: event.id, forward: payload })
    CliAttemptTimeoutJob.set(wait: CliAttemptTimeoutJob::TIMEOUT).perform_later(attempt.id, retry_count)
  end

  # A non-active connection neither sends nor fails anything: no HTTP, no
  # failure counters, no alerts. Paused keeps the delivery as a :held slot
  # released on resume; disabled drops it outright.
  def hold_or_drop(event, connection, replay)
    pending = Attempt.where(event: event, connection: connection, status: :pending)
                     .order(:attempt_number).last
    if connection.status_paused?
      if pending
        pending.update!(status: :held)
      else
        Attempt.create!(
          event: event, connection: connection,
          attempt_number: next_attempt_number(event, connection),
          status: :held, attempted_at: Time.current, replay: replay
        )
      end
    else
      pending&.destroy!
    end
  rescue ActiveRecord::RecordNotUnique
    # Concurrent jobs raced to hold the same slot; one held row is enough.
  end

  # A manual retry pre-creates a :pending attempt to claim the delivery slot (Slice 5 R5).
  # Consume it if present; automatic deliveries (ingest, scheduled retries) have none -> build fresh.
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
