require "digest"

# A per-user, per-device API credential issued by the CLI device flow. Unlike
# org-wide ApiKeys, requests made with one are attributed to the user and
# enforce that user's project role.
class CliToken < ApplicationRecord
  belongs_to :user
  belongs_to :organization

  validates :name, presence: true

  scope :active, -> { where(revoked_at: nil) }

  def self.issue!(user:, organization:, name:)
    raw = "hkc_#{SecureRandom.hex(24)}"
    token = create!(user: user, organization: organization, name: name,
                    token_digest: digest(raw), prefix: raw.first(12))
    [ token, raw ]
  end

  def self.digest(raw) = Digest::SHA256.hexdigest(raw)

  def self.authenticate(raw)
    return nil if raw.blank?

    active.find_by(token_digest: digest(raw))
  end

  def active? = revoked_at.nil?

  def revoke! = update!(revoked_at: Time.current)

  # Cheap-enough freshness signal without a write per request.
  def touch_last_used!
    update_column(:last_used_at, Time.current) if last_used_at.nil? || last_used_at < 5.minutes.ago
  end
end
