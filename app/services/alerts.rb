# Single fan-out for incident alerts: every alert goes to email and, when the
# org has configured one, to its alert webhook. New alert types must go
# through here so both channels always fire on the same transitions.
module Alerts
  def self.connection_unhealthy(connection)
    AlertMailer.connection_unhealthy(connection).deliver_later
    webhook(connection.project.organization, "connection.unhealthy",
            { "source" => connection.source.name,
              "destination" => connection.destination.name,
              "consecutive_failures" => connection.consecutive_failures,
              "unhealthy_since" => connection.unhealthy_since&.utc&.iso8601 })
  end

  def self.connection_recovered(connection)
    AlertMailer.connection_recovered(connection).deliver_later
    webhook(connection.project.organization, "connection.recovered",
            { "source" => connection.source.name,
              "destination" => connection.destination.name })
  end

  def self.webhook_quarantined(quarantined_webhook)
    AlertMailer.webhook_quarantined(quarantined_webhook).deliver_later
    webhook(quarantined_webhook.source.project.organization, "webhook.quarantined",
            { "source" => quarantined_webhook.source.name,
              "reason" => quarantined_webhook.reason,
              "received_at" => quarantined_webhook.received_at.utc.iso8601 })
  end

  # Sample payload so a receiver can be verified without a real incident.
  def self.test(organization)
    webhook(organization, "test",
            { "message" => "Test alert from Hookrail. Your receiver is wired up." })
  end

  def self.webhook(organization, type, data)
    return unless organization.alert_webhook_configured?

    AlertWebhookJob.perform_later(organization.id, type, data, Time.current.utc.iso8601)
  end
  private_class_method :webhook
end
