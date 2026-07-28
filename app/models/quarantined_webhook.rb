class QuarantinedWebhook < ApplicationRecord
  belongs_to :source

  # Quarantine is driven by an unauthenticated endpoint: anyone holding the
  # source token can produce rejected requests as fast as they like. Alerting
  # per row turns that into a mail bomb against every org admin and an
  # amplifier pointed at the org's alert receiver, so the email and webhook
  # ride the same one-per-open-issue dedupe that chat already uses.
  after_create_commit do
    opened = Issue.record!(type: :webhook_quarantined, subject: source, summary: reason)
    Alerts.webhook_quarantined(self) if opened
  end
end
