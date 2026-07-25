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

  # Personal orgs have one user, the owner. GitHub OAuth may withhold the
  # email address, in which case there is no one to mail.
  def alert_mail(project, subject)
    to = project.organization.owner.email
    return if to.blank?

    mail(to: to, subject: subject)
  end
end
