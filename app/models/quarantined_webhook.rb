class QuarantinedWebhook < ApplicationRecord
  belongs_to :source

  after_create_commit { AlertMailer.webhook_quarantined(self).deliver_later }
end
