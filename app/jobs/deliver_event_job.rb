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

  def perform(event_id, connection_id)
    event = Event.find(event_id)
    connection = Connection.find(connection_id)

    attempt = Attempt.create!(
      event: event,
      connection: connection,
      attempt_number: executions,
      status: :delivering,
      attempted_at: Time.current
    )

    result = Delivery::Client.deliver(event: event, destination: connection.destination)

    if result.success?
      attempt.update!(
        status: :succeeded,
        response_status: result.status,
        response_body: result.body_excerpt,
        duration_ms: result.duration_ms
      )
    else
      attempt.update!(
        status: :failed,
        response_status: result.status,
        response_body: result.body_excerpt,
        error: result.error,
        duration_ms: result.duration_ms
      )
      raise DeliveryError
    end
  end
end
