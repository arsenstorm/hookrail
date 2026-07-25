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

  DEDUPE_KEYS = %w[window key].freeze
  DEDUPE_WINDOW_RANGE = 1..86_400

  store_accessor :dedupe, :window, :key, prefix: true

  before_validation :normalize_dedupe
  validate :dedupe_shape

  def dedupe_enabled? = dedupe.present?

  # The identity of an incoming request under this source's dedupe config, or
  # nil when none can be established (dedupe off, or the configured key value
  # is absent/empty). Prefixes keep key-mode and body-hash identities from
  # colliding if the config changes mid-window.
  def dedupe_identity(headers:, body:)
    return nil unless dedupe_enabled?
    return "sha256:#{Digest::SHA256.hexdigest(body.to_s)}" if dedupe_key.blank?

    value = dedupe_header_value(headers) || dedupe_body_value(body)
    value.presence && "key:#{value}"
  end

  private

  # Normalizes Parameters / symbol keys; {} clears (dedupe off). An enabled
  # config without a window gets the 60-second default.
  def normalize_dedupe
    cfg = dedupe.to_h.stringify_keys.compact_blank
    cfg["window"] = Integer(cfg["window"], exception: false) || cfg["window"] || 60 if cfg.present?
    self.dedupe = cfg
  end

  def dedupe_shape
    cfg = dedupe.to_h
    return if cfg.blank?

    unknown = cfg.keys - DEDUPE_KEYS
    errors.add(:dedupe, "has unknown keys: #{unknown.join(", ")}") if unknown.any?
    unless cfg["window"].is_a?(Integer) && DEDUPE_WINDOW_RANGE.cover?(cfg["window"])
      errors.add(:dedupe, "window must be an integer between 1 and 86400 seconds")
    end
    errors.add(:dedupe, "key must be a string") if cfg["key"].present? && !cfg["key"].is_a?(String)
  end

  # The key names a header first (case-insensitive), a body dot path second.
  def dedupe_header_value(headers)
    headers.to_h.each { |name, value| return value.to_s if name.casecmp?(dedupe_key) }
    nil
  end

  def dedupe_body_value(body)
    json = JSON.parse(body.to_s)
    value = dedupe_key.split(".").reduce(json) { |node, k| node.is_a?(Hash) ? node[k] : nil }
    value&.to_s
  rescue JSON::ParserError
    nil
  end
end
