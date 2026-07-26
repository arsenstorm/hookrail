# Single fan-out for incident alerts: every alert goes to email and, when the
# org has configured one, to its alert webhook. Chat (Slack/Discord) is a
# separate channel that only fires when an Issue opens — never on increment,
# ack, or resolve — so one open issue absorbs repeats without spamming chat.
# New alert types must go through here so all channels always fire on the
# same transitions.
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
    chat(organization, "Test alert from Hookrail. Your receiver is wired up.")
  end

  # Chat channels fire when an issue opens — never on increment, ack, or
  # resolve — so one open issue absorbs repeats without spamming.
  def self.issue_opened(issue)
    chat(issue.project.organization,
         "New issue: #{issue.issue_type.humanize} — #{issue.subject_name} (#{issue.project.name})\n" \
         "#{issue.summary}\n#{issue_link(issue)}")
  end

  def self.webhook(organization, type, data)
    return unless organization.alert_webhook_configured?

    AlertWebhookJob.perform_later(organization.id, type, data, Time.current.utc.iso8601)
  end
  private_class_method :webhook

  def self.chat(organization, text)
    ChatAlertJob.perform_later(organization.id, "slack", text) if organization.slack_webhook_url.present?
    ChatAlertJob.perform_later(organization.id, "discord", text) if organization.discord_webhook_url.present?
  end
  private_class_method :chat

  def self.issue_link(issue)
    Rails.application.routes.url_helpers.issue_url(issue, **Rails.application.config.action_mailer.default_url_options)
  end
  private_class_method :issue_link
end
