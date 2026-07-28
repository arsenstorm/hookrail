class IngestController < ActionController::Base
  # Public webhook receiver: external callers, so no CSRF token / session.
  skip_forgery_protection

  MAX_BODY_BYTES = 5.megabytes
  # Generous enough that no real provider trips it, low enough that a single
  # token cannot be used to fill the database. Keyed per source token, so one
  # noisy sender cannot starve another tenant.
  MAX_REQUESTS_PER_MINUTE = 600

  # Runs before anything touches `params`, because reading params parses the
  # request body: a 100MB JSON post would be inflated into an object graph
  # before a size check on the parsed result could ever reject it.
  before_action :reject_oversized_body

  rate_limit to: MAX_REQUESTS_PER_MINUTE, within: 1.minute,
             by: -> { request.path_parameters[:token] },
             with: -> { head :too_many_requests }

  # Headers that authenticate the *sender to us*. Storing them would keep a
  # third party's credential in cleartext forever, render it to every project
  # viewer, and return it from the events API; forwarding them would leak it to
  # the destination, which has its own credentials.
  SENSITIVE_HEADERS = %w[Authorization Proxy-Authorization Cookie].freeze
  REDACTED = "[redacted]".freeze

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

    headers = captured_headers
    identity = source.dedupe_identity(headers: headers, body: body)
    # A duplicate only matches non-duplicate originals: the window is anchored
    # to the original, never extended by later copies. Concurrent copies can
    # race past this check; acceptable at current scale.
    duplicate = identity.present? &&
                source.events.where(dedupe_key: identity, duplicate: false)
                      .exists?(received_at: source.dedupe_window.seconds.ago..)

    event = source.events.create!(
      http_method: request.request_method,
      path: request.path,
      query_string: request.query_string.presence,
      headers: headers,
      body: body.presence,
      received_at: Time.current,
      dedupe_key: identity,
      duplicate: duplicate
    )

    unless duplicate
      # Paused connections still match: their DeliverEventJob converts the delivery into a held attempt instead of sending.
      source.connections.where(status: %w[active paused]).find_each do |connection|
        next unless connection.routes?(event)

        DeliverEventJob.perform_later(event.id, connection.id)
      end
    end

    head :ok
  end

  private

  # Content-Length is a claim, not a guarantee, so the real body is still
  # measured after reading; this only stops us buffering and parsing an
  # obviously oversized request in the first place.
  def reject_oversized_body
    declared = request.content_length.to_i
    head(:payload_too_large) if declared > MAX_BODY_BYTES
  end

  # Reconstruct the incoming HTTP headers from the Rack env.
  def captured_headers
    request.headers.env.each_with_object({}) do |(key, value), acc|
      next unless key.start_with?("HTTP_") || %w[CONTENT_TYPE CONTENT_LENGTH].include?(key)
      next unless value.is_a?(String)

      name = key.delete_prefix("HTTP_").split("_").map(&:capitalize).join("-")
      acc[name] = SENSITIVE_HEADERS.include?(name) ? REDACTED : value
    end
  end
end
