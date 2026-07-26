require "net/http"

# Posts one plain-text notification to the org's Slack and/or Discord incoming
# webhook. Failures are bounded and terminal, exactly like AlertWebhookJob:
# chat delivery must never generate alerts or block the event pipeline.
class ChatAlertJob < ApplicationJob
  queue_as :default

  TIMEOUT_SECONDS = 10
  MAX_ATTEMPTS = 3

  class ChatDeliveryError < StandardError; end

  retry_on ChatDeliveryError, attempts: MAX_ATTEMPTS, wait: :polynomially_longer do |job, error|
    organization_id, channel = job.arguments
    Rails.logger.warn(
      "chat alert dropped after #{MAX_ATTEMPTS} attempts: org=#{organization_id} channel=#{channel} (#{error.message})"
    )
  end

  def perform(organization_id, channel, text)
    organization = Organization.find(organization_id)
    url = channel == "slack" ? organization.slack_webhook_url : organization.discord_webhook_url
    return if url.blank?

    # Slack incoming webhooks take {"text": ...}, Discord takes {"content": ...}.
    body = JSON.generate({ (channel == "slack" ? "text" : "content") => text })
    response = post_json(url, body)
    unless response.code.to_i.between?(200, 299)
      raise ChatDeliveryError, "HTTP #{response.code}"
    end
  rescue ChatDeliveryError
    raise
  rescue ActiveRecord::RecordNotFound
    nil
  rescue => e
    raise ChatDeliveryError, "#{e.class}: #{e.message}"
  end

  private

  def post_json(url, body)
    uri = URI.parse(url)
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body = body

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = TIMEOUT_SECONDS
    http.read_timeout = TIMEOUT_SECONDS
    http.request(request)
  end
end
