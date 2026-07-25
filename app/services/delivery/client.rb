require "net/http"
require "openssl"

module Delivery
  class Client
    TIMEOUT_SECONDS = 10
    MAX_RESPONSE_BODY = 10_000

    # Hop-by-hop / connection-specific headers that must not be forwarded: Net::HTTP
    # recomputes Content-Length and Host for the new request, and the rest don't apply
    # to a fresh connection. Compared case-insensitively.
    SKIP_FORWARD_HEADERS = %w[host content-length connection transfer-encoding keep-alive].freeze

    def self.deliver(event:, destination:, replay: false)
      new(event, destination, replay).deliver
    end

    def initialize(event, destination, replay = false)
      @event = event
      @destination = destination
      @replay = replay
    end

    def deliver
      uri = URI.parse(@destination.url)
      body = @event.body.to_s
      request = build_request(uri, body)

      http = Net::HTTP.new(uri.host, uri.port)
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

    private

    def build_request(uri, body)
      request = http_method_class.new(uri)

      # Forward the original inbound headers (Content-Type, etc.), minus hop-by-hop.
      @event.headers.each do |name, value|
        next if SKIP_FORWARD_HEADERS.include?(name.to_s.downcase)
        request[name] = value.to_s
      end

      # Destination's static headers override anything forwarded.
      @destination.headers.each { |name, value| request[name] = value.to_s }

      timestamp = Time.current.to_i.to_s
      request["X-Hookrail-Timestamp"] = timestamp
      request["X-Hookrail-Signature"] = "sha256=#{signature(body, timestamp)}"
      request["X-Hookrail-Replay"] = "true" if @replay
      request.body = body
      request
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
