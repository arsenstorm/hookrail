class Organization < ApplicationRecord
  belongs_to :owner, class_name: "User"
  has_many :projects, dependent: :destroy
  has_many :api_keys, dependent: :destroy
  has_many :cli_tokens, dependent: :destroy
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :invitations, dependent: :destroy

  validates :name, presence: true

  # Shared secret used to sign outbound alert webhooks; never looked up by value.
  encrypts :alert_webhook_secret

  validates :alert_webhook_url, format: { with: %r{\Ahttps?://\S+\z}i, message: "must be an http(s) URL" },
            allow_blank: true

  validates :slack_webhook_url, :discord_webhook_url,
            format: { with: %r{\Ahttps?://\S+\z}i, message: "must be an http(s) URL" }, allow_blank: true

  validates :retention_days, inclusion: { in: [ 7, 30, 90 ], message: "must be 7, 30, or 90 days" }

  # The secret lives and dies with the URL: generated when a URL is first set,
  # cleared when it is removed, kept across URL edits so receivers don't break.
  before_validation do
    self.slack_webhook_url = slack_webhook_url.presence
    self.discord_webhook_url = discord_webhook_url.presence
    self.alert_webhook_url = alert_webhook_url.presence
    if alert_webhook_url.blank?
      self.alert_webhook_secret = nil
    elsif alert_webhook_secret.blank?
      self.alert_webhook_secret = SecureRandom.hex(24)
    end
  end

  def alert_webhook_configured? = alert_webhook_url.present?
  def chat_webhook_configured? = slack_webhook_url.present? || discord_webhook_url.present?

  # Owners and admins with a known address — GitHub OAuth may withhold emails.
  def alert_recipients
    memberships.where(role: %w[owner admin]).joins(:user)
               .where.not(users: { email: [ nil, "" ] }).pluck("users.email")
  end
end
