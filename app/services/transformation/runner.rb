module Transformation
  # Runs a connection's `transform(request)` JavaScript in an embedded V8
  # isolate: no network, no filesystem, no require/import, and a hard
  # wall-clock timeout. Only headers and body of the returned object affect
  # the outbound request; path/query are inputs for deriving values, since
  # deliveries always go to the destination's URL.
  class Runner
    TIMEOUT_MS = 1_000

    def self.run(code, event)
      new(code).run(event)
    end

    def self.check!(code)
      new(code).check!
    end

    def initialize(code)
      @code = code.to_s
    end

    # -> { headers: Hash<String,String>, body: String }
    def run(event)
      context = build_context
      result = context.call("transform", request_for(event))
      normalize(result)
    rescue MiniRacer::Error => e
      raise Error, error_message(e)
    ensure
      context&.dispose
    end

    # Raises Transformation::Error unless the code parses and defines a
    # transform function.
    def check!
      context = build_context
      unless context.eval("typeof transform === 'function'")
        raise Error, "must define a transform function"
      end
    rescue MiniRacer::Error => e
      raise Error, error_message(e)
    ensure
      context&.dispose
    end

    private

    def build_context
      context = MiniRacer::Context.new(timeout: TIMEOUT_MS)
      context.eval(@code)
      context
    end

    def request_for(event)
      {
        "headers" => event.headers.to_h,
        "body" => parsed_body(event.body.to_s),
        "path" => event.path.to_s,
        "query" => event.query_string.to_s
      }
    end

    # JSON bodies arrive parsed so transforms can address fields directly;
    # anything else is the raw string.
    def parsed_body(raw)
      JSON.parse(raw)
    rescue JSON::ParserError
      raw
    end

    def normalize(result)
      raise Error, "transform must return an object" unless result.is_a?(Hash)

      headers = result["headers"]
      raise Error, "headers must be an object" unless headers.nil? || headers.is_a?(Hash)

      { headers: (headers || {}).transform_values(&:to_s),
        body: serialize_body(result["body"]) }
    end

    def serialize_body(body)
      case body
      when nil then ""
      when String then body
      else JSON.generate(body)
      end
    end

    def error_message(error)
      case error
      when MiniRacer::ScriptTerminatedError then "timed out after #{TIMEOUT_MS}ms"
      else error.message.to_s
      end
    end
  end
end
