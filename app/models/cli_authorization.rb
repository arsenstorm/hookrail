require "digest"

# One in-flight CLI login. Short-lived: approved rows convert to a CliToken at
# the CLI's next poll and are destroyed; denied/expired rows are destroyed on
# poll or swept by the daily prune.
class CliAuthorization < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :organization, optional: true

  # No vowels or ambiguous glyphs: codes can't spell words or be misread.
  USER_CODE_ALPHABET = "BCDFGHJKLMNPQRSTVWXZ23456789"
  TTL = 15.minutes

  enum :status, { pending: "pending", approved: "approved", denied: "denied" }

  # Returns [record, raw_device_code]. The device code is the CLI's polling
  # secret; only its digest is stored.
  def self.start!(device_name:)
    raw = SecureRandom.hex(32)
    record = create!(device_code_digest: digest(raw), user_code: generate_user_code,
                     device_name: device_name, expires_at: TTL.from_now)
    [ record, raw ]
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def self.digest(raw) = Digest::SHA256.hexdigest(raw)

  # Poll outcome: :pending, :gone (invalid/expired/denied — indistinguishable
  # on purpose), or [cli_token, raw_token] issued exactly once.
  def self.claim_token!(raw_device_code)
    auth = find_by(device_code_digest: digest(raw_device_code.to_s))
    return :gone unless auth

    if auth.expires_at.past? || auth.denied?
      auth.destroy!
      return :gone
    end
    return :pending if auth.pending?

    result = CliToken.issue!(user: auth.user, organization: auth.organization, name: auth.device_name)
    auth.destroy!
    result
  end

  # SecureRandom, not Array#sample: sample draws from Ruby's Mersenne Twister,
  # and this code is what authorises a CLI session. A predictable one lets an
  # attacker approve someone else's pending flow into an org they control.
  def self.generate_user_code
    alphabet = USER_CODE_ALPHABET.chars
    core = Array.new(8) { alphabet[SecureRandom.random_number(alphabet.size)] }.join
    "#{core.first(4)}-#{core.last(4)}"
  end

  # "abcd1234", "ABCD-1234 " etc. all resolve to the canonical form.
  def self.normalize_code(input)
    core = input.to_s.upcase.gsub(/[^A-Z0-9]/, "")
    "#{core.first(4)}-#{core.last(4)}"
  end
end
