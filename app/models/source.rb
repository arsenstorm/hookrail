class Source < ApplicationRecord
  belongs_to :project
  has_many :events, dependent: :destroy
  has_many :connections, dependent: :destroy
  has_many :quarantined_webhooks, dependent: :destroy

  validates :name, presence: true

  # Generates a unique 24-char token in before_create; DB unique index enforces integrity.
  has_secure_token :token

  store_accessor :verification, :secret, :header, :algorithm, :encoding,
                 :header_format, :signature_prefix, :signature_key,
                 :timestamp_key, :timestamp_header, :payload_template,
                 :tolerance_seconds, prefix: true

  # Drop blank form inputs so presence of `secret` alone means "enabled".
  before_validation { self.verification = verification.to_h.compact_blank }

  with_options if: -> { verification_secret.present? } do
    validates :verification_header, presence: true
    validates :verification_algorithm, inclusion: { in: %w[sha1 sha256 sha512] }, allow_blank: true
    validates :verification_encoding, inclusion: { in: %w[hex base64] }, allow_blank: true
    validates :verification_header_format, inclusion: { in: %w[value kv] }, allow_blank: true
    validates :verification_tolerance_seconds, numericality: { only_integer: true, greater_than: 0 }, allow_blank: true
  end

  def verification_enabled?
    verification_secret.present?
  end
end
