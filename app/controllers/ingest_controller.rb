class IngestController < ActionController::Base
  # Public webhook receiver: external callers, so no CSRF token / session.
  skip_forgery_protection

  MAX_BODY_BYTES = 5.megabytes

  def create
    source = Source.find_by(token: params[:token])
    return head(:not_found) unless source

    body = request.raw_post.to_s
    return head(:payload_too_large) if body.bytesize > MAX_BODY_BYTES

    if source.verification_enabled?
      result = Ingest::Verifier.verify(source: source, request: request, body: body)
      unless result.ok?
        source.quarantined_webhooks.create!(
          http_method: request.request_method,
          path: request.path,
          query_string: request.query_string.presence,
          headers: captured_headers,
          body: body.presence,
          reason: result.reason,
          received_at: Time.current
        )
        return head(:unauthorized)
      end
    end

    event = source.events.create!(
      http_method: request.request_method,
      path: request.path,
      query_string: request.query_string.presence,
      headers: captured_headers,
      body: body.presence,
      received_at: Time.current
    )

    source.connections.where(active: true).find_each do |connection|
      next unless connection.routes?(event)

      DeliverEventJob.perform_later(event.id, connection.id)
    end

    head :ok
  end

  private

  # Reconstruct the incoming HTTP headers from the Rack env.
  def captured_headers
    request.headers.env.each_with_object({}) do |(key, value), acc|
      next unless key.start_with?("HTTP_") || %w[CONTENT_TYPE CONTENT_LENGTH].include?(key)
      next unless value.is_a?(String)

      name = key.delete_prefix("HTTP_").split("_").map(&:capitalize).join("-")
      acc[name] = value
    end
  end
end
