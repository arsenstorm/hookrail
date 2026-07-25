class Organization < ApplicationRecord
  belongs_to :owner, class_name: "User"
  has_many :projects, dependent: :destroy
  has_many :api_keys, dependent: :destroy

  validates :name, presence: true

  validates :alert_webhook_url, format: { with: %r{\Ahttps?://\S+\z}i, message: "must be an http(s) URL" },
            allow_blank: true

  # The secret lives and dies with the URL: generated when a URL is first set,
  # cleared when it is removed, kept across URL edits so receivers don't break.
  before_validation do
    self.alert_webhook_url = alert_webhook_url.presence
    if alert_webhook_url.blank?
      self.alert_webhook_secret = nil
    elsif alert_webhook_secret.blank?
      self.alert_webhook_secret = SecureRandom.hex(24)
    end
  end

  def alert_webhook_configured? = alert_webhook_url.present?
end
