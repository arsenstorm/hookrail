class AlertMailer < ApplicationMailer
  def connection_unhealthy(connection)
    @connection = connection
    alert_mail(connection.project, "[Hookrail] Delivery failing: #{connection.source.name} → #{connection.destination.name}")
  end

  def connection_recovered(connection)
    @connection = connection
    alert_mail(connection.project, "[Hookrail] Delivery recovered: #{connection.source.name} → #{connection.destination.name}")
  end

  def webhook_quarantined(quarantined_webhook)
    @quarantined_webhook = quarantined_webhook
    @source = quarantined_webhook.source
    alert_mail(@source.project, "[Hookrail] Webhook quarantined: #{@source.name}")
  end

  private

  # Alerts go to every owner and admin with an email — incident response is a
  # team activity. GitHub OAuth may withhold addresses; skip when nobody has one.
  def alert_mail(project, subject)
    to = project.organization.alert_recipients
    return if to.empty?

    mail(to: to, subject: subject)
  end
end
