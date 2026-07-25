require "digest"

class ApiKey < ApplicationRecord
  belongs_to :organization

  validates :name, presence: true

  scope :active, -> { where(revoked_at: nil) }

  # Raw keys are shown once at creation and stored only as a SHA-256 digest;
  # `prefix` keeps the first characters so keys can be told apart in the UI.
  def self.issue!(organization:, name:)
    raw = "hk_#{SecureRandom.hex(24)}"
    key = create!(organization: organization, name: name,
                  token_digest: digest(raw), prefix: raw.first(12))
    [ key, raw ]
  end

  def self.digest(raw) = Digest::SHA256.hexdigest(raw)

  def self.authenticate(raw)
    return nil if raw.blank?

    active.find_by(token_digest: digest(raw))
  end

  def active? = revoked_at.nil?

  def revoke! = update!(revoked_at: Time.current)
end
