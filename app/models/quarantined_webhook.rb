class QuarantinedWebhook < ApplicationRecord
  belongs_to :source

  after_create_commit { Alerts.webhook_quarantined(self) }
end
