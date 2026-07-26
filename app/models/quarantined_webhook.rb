class QuarantinedWebhook < ApplicationRecord
  belongs_to :source

  after_create_commit do
    Alerts.webhook_quarantined(self)
    Issue.record!(type: :webhook_quarantined, subject: source, summary: reason)
  end
end
