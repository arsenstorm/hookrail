require "net/http"
require "openssl"

# Posts one alert to the org's webhook. Failures are bounded and terminal:
# exhausted retries drop the alert with a log line — alert delivery must never
# generate alerts, touch connection health, or block the event pipeline.
class AlertWebhookJob < ApplicationJob
  queue_as :default

  TIMEOUT_SECONDS = 10
  MAX_ATTEMPTS = 3

  class AlertDeliveryError < StandardError; end

  retry_on AlertDeliveryError, attempts: MAX_ATTEMPTS, wait: :polynomially_longer do |job, error|
    organization_id, type = job.arguments
    Rails.logger.warn(
      "alert webhook dropped after #{MAX_ATTEMPTS} attempts: org=#{organization_id} type=#{type} (#{error.message})"
    )
  end

  def perform(organization_id, type, data, occurred_at)
    organization = Organization.find(organization_id)
    return unless organization.alert_webhook_configured?

    body = JSON.generate({ "type" => type, "occurred_at" => occurred_at, "data" => data })
    response = post_alert(organization, body)
    unless response.code.to_i.between?(200, 299)
      raise AlertDeliveryError, "HTTP #{response.code}"
    end
  rescue AlertDeliveryError
    raise
  rescue ActiveRecord::RecordNotFound
    nil
  rescue => e
    raise AlertDeliveryError, "#{e.class}: #{e.message}"
  end

  private

  # Same signing scheme as event deliveries, keyed by the per-org secret.
  def post_alert(organization, body)
    uri = URI.parse(organization.alert_webhook_url)
    request = Net::HTTP::Post.new(uri)
    timestamp = Time.current.to_i.to_s
    request["Content-Type"] = "application/json"
    request["X-Hookrail-Timestamp"] = timestamp
    request["X-Hookrail-Signature"] =
      "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", organization.alert_webhook_secret.to_s, "#{timestamp}.#{body}")}"
    request.body = body

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = TIMEOUT_SECONDS
    http.read_timeout = TIMEOUT_SECONDS
    http.request(request)
  end
end
