require "net/http"
require "openssl"

module Delivery
  class Client
    TIMEOUT_SECONDS = 10
    MAX_RESPONSE_BODY = 10_000

    # Hop-by-hop / connection-specific headers that must not be forwarded, plus the
    # proxy trail our own edge (Cloudflare, Railway) stamps on inbound requests:
    # forwarded Cf-*/X-Forwarded-* headers read as spoofing to WAFs at CDN-fronted
    # destinations (they answer 403), and an explicit Accept-Encoding disables
    # Net::HTTP's transparent decompression, landing compressed bytes in
    # response_body. Compared case-insensitively.
    # Also dropped: headers that authenticated the sender to us. They are the
    # sender's credential, not ours to forward, and the destination has its own
    # auth configured on the destination record.
    SKIP_FORWARD_HEADERS = %w[host content-length connection transfer-encoding keep-alive
                              accept-encoding x-real-ip x-request-start x-sendfile-type
                              cdn-loop authorization proxy-authorization cookie].freeze
    SKIP_FORWARD_PREFIXES = %w[cf- x-forwarded- x-railway-].freeze

    def self.deliver(event:, destination:, replay: false, transformed: nil)
      new(event, destination, replay, transformed).deliver
    end

    def self.payload_for(event:, destination:, replay: false, transformed: nil)
      new(event, destination, replay, transformed).payload
    end

    def initialize(event, destination, replay = false, transformed = nil)
      @event = event
      @destination = destination
      @replay = replay
      @transformed = transformed
    end

    def deliver
      uri = URI.parse(@destination.url)
      # Resolve and validate before connecting, then pin the address so
      # Net::HTTP cannot re-resolve to somewhere else between check and
      # connect. Host header and TLS SNI still come from the URL.
      address = AddressGuard.resolve!(@destination.url)
      request = build_request(uri, payload)

      http = Net::HTTP.new(uri.host, uri.port)
      http.ipaddr = address
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = TIMEOUT_SECONDS
      http.read_timeout = TIMEOUT_SECONDS

      started = monotonic_ms
      response = http.request(request)
      Result.new(
        status: response.code.to_i,
        body_excerpt: response.body.to_s[0, MAX_RESPONSE_BODY],
        error: nil,
        duration_ms: monotonic_ms - started
      )
    rescue => e
      Result.new(
        status: nil,
        body_excerpt: nil,
        error: "#{e.class}: #{e.message}",
        duration_ms: (defined?(started) && started ? monotonic_ms - started : nil)
      )
    end

    # Everything the wire needs, before transport: forwarded headers minus the
    # skip lists, destination overrides, signing, and the (possibly
    # transformed) body. Shared by the HTTP client and the CLI tunnel
    # broadcast so both sign and filter identically. Configured destination
    # auth overrides any manually set Authorization header.
    def payload
      body = @transformed ? @transformed[:body] : @event.body.to_s
      headers = {}
      (@transformed ? @transformed[:headers] : @event.headers).each do |name, value|
        headers[name] = value.to_s if forwardable?(name)
      end
      @destination.headers.each { |name, value| headers[name] = value.to_s }
      if (authorization = @destination.authorization_header)
        headers["Authorization"] = authorization
      end
      timestamp = Time.current.to_i.to_s
      headers["X-Hookrail-Timestamp"] = timestamp
      headers["X-Hookrail-Signature"] = "sha256=#{signature(body, timestamp)}"
      headers["X-Hookrail-Replay"] = "true" if @replay
      { http_method: @event.http_method, path: @event.path, query_string: @event.query_string,
        headers: headers, body: body }
    end

    private

    def build_request(uri, payload)
      request = http_method_class.new(uri)
      payload[:headers].each { |name, value| request[name] = value }
      request.body = payload[:body]
      request
    end

    def forwardable?(name)
      n = name.to_s.downcase
      return false if SKIP_FORWARD_HEADERS.include?(n)
      SKIP_FORWARD_PREFIXES.none? { |prefix| n.start_with?(prefix) }
    end

    def http_method_class
      Net::HTTP.const_get(@event.http_method.to_s.capitalize)
    rescue NameError
      Net::HTTP::Post
    end

    def signature(body, timestamp)
      OpenSSL::HMAC.hexdigest("SHA256", @destination.signing_secret.to_s, "#{timestamp}.#{body}")
    end

    def monotonic_ms
      (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).round
    end
  end
end
