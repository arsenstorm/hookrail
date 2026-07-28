require "openssl"
require "base64"

module Ingest
  class Verifier
    Result = Data.define(:ok, :reason) do
      def ok? = ok
    end

    ALGORITHMS = { "sha1" => "SHA1", "sha256" => "SHA256", "sha512" => "SHA512" }.freeze

    # Applied whenever a request carries a timestamp but the source never set a
    # window. Without it a captured request replays forever: a signature alone
    # says "this body is authentic", never "this delivery is fresh".
    DEFAULT_TOLERANCE_SECONDS = 300

    # A timestamp is interpolated into the signed payload, so it has to be
    # exactly a number. Anything else lets it carry template-significant bytes.
    NUMERIC = /\A\d+\z/

    def self.verify(source:, request:, body:)
      new(source, request, body).verify
    end

    def initialize(source, request, body)
      @source = source
      @request = request
      @body = body
    end

    def verify
      header_name = @source.verification_header.to_s
      header_value = @request.headers[header_name].to_s
      return fail!("missing #{header_name} header") if header_value.blank?

      signatures, embedded_timestamp = extract(header_value)
      return fail!("no signature found in #{header_name} header") if signatures.empty?

      timestamp = explicit_timestamp || embedded_timestamp
      configured_tolerance = @source.verification_tolerance_seconds.presence

      # Fail closed when a timestamp was configured but did not arrive.
      return fail!("missing timestamp") if configured_tolerance && timestamp.blank?

      if timestamp.present?
        return fail!("malformed timestamp") unless timestamp.to_s.match?(NUMERIC)

        tolerance = (configured_tolerance || DEFAULT_TOLERANCE_SECONDS).to_i
        return fail!("timestamp outside tolerance") if (Time.current.to_i - timestamp.to_i).abs > tolerance
      end

      expected = compute(signed_payload(timestamp))
      return fail!("signature mismatch") unless signatures.any? { |sig| secure_compare(expected, sig) }

      Result.new(ok: true, reason: nil)
    end

    private

    def fail!(reason) = Result.new(ok: false, reason: reason)

    # kv format collects every value under signature_key so multiple
    # rolling-secret signatures all get compared.
    def extract(header_value)
      if @source.verification_header_format == "kv"
        pairs = header_value.split(",").filter_map do |part|
          k, v = part.split("=", 2)
          [ k.to_s.strip, v.to_s.strip ] if v
        end
        sig_key = @source.verification_signature_key.presence || "v1"
        signatures = pairs.select { |k, _| k == sig_key }.map(&:last).reject(&:empty?)
        timestamp = @source.verification_timestamp_key.presence &&
          pairs.to_h[@source.verification_timestamp_key]
        [ signatures, timestamp ]
      else
        value = header_value.strip
        prefix = @source.verification_signature_prefix.to_s
        value = value.delete_prefix(prefix) if prefix.present?
        [ value.empty? ? [] : [ value ], nil ]
      end
    end

    def explicit_timestamp
      header = @source.verification_timestamp_header.presence
      header && @request.headers[header].presence
    end

    # One pass over the template, so a value substituted for one placeholder is
    # never rescanned for another. Two chained gsubs let an attacker move the
    # field boundary: with the template "{timestamp}.{body}", sending
    # timestamp="1700000000.{"amount":10" and the rest of the body separately
    # reconstructs byte-identical signed bytes, so the HMAC still verifies while
    # the body actually stored and forwarded has been truncated.
    #
    # Block form of sub: the body may contain backslash sequences that the
    # string-replacement form would interpret as backreferences.
    PLACEHOLDER = /\{(timestamp|body)\}/

    def signed_payload(timestamp)
      template = @source.verification_payload_template.presence || "{body}"
      values = { "timestamp" => timestamp.to_s, "body" => @body }
      template.gsub(PLACEHOLDER) { values.fetch(Regexp.last_match(1)) }
    end

    def compute(payload)
      algorithm = ALGORITHMS.fetch(@source.verification_algorithm.presence || "sha256")
      digest = OpenSSL::HMAC.digest(algorithm, @source.verification_secret.to_s, payload)
      if (@source.verification_encoding.presence || "hex") == "base64"
        Base64.strict_encode64(digest)
      else
        digest.unpack1("H*")
      end
    end

    def secure_compare(a, b)
      ActiveSupport::SecurityUtils.secure_compare(a, b)
    end
  end
end
