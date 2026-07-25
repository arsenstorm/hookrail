class Destination < ApplicationRecord
  belongs_to :project
  has_many :connections, dependent: :destroy

  validates :name, presence: true
  validates :url, presence: true

  # Secret used to HMAC-sign forwarded payloads; auto-generated, DB unique index enforces integrity.
  has_secure_token :signing_secret

  RATE_LIMIT_RANGES = { "second" => 1..100, "minute" => 1..6000 }.freeze

  # Blank limit clears the period; a limit without a period defaults to per-second.
  before_validation do
    self.rate_limit_period = rate_limit.blank? ? nil : rate_limit_period.presence || "second"
  end
  validate :rate_limit_bounds

  def rate_limited? = rate_limit.present?

  # Atomically claim one delivery slot in the current fixed window. Returns 0
  # when claimed, else seconds to wait for the next window. The guarded
  # single-row UPDATE arbitrates concurrent jobs. ponytail: fixed windows can
  # burst up to 2x across a boundary; move to a token bucket if that matters.
  def claim_delivery_slot!
    return 0 unless rate_limited?

    period = rate_limit_period == "minute" ? 60 : 1
    window_start = Time.current.to_i / period * period
    window_time = Time.zone.at(window_start)
    claimed = self.class.where(id: id)
      .where("rate_window_started_at IS DISTINCT FROM ? OR rate_window_count < ?", window_time, rate_limit)
      .update_all([ "rate_window_count = CASE WHEN rate_window_started_at = ? THEN rate_window_count + 1 ELSE 1 END, rate_window_started_at = ?",
                    window_time, window_time ])
    return 0 if claimed == 1

    [ window_start + period - Time.current.to_f, 0.1 ].max
  end

  private

  def rate_limit_bounds
    return if rate_limit.blank?

    range = RATE_LIMIT_RANGES[rate_limit_period]
    return errors.add(:rate_limit_period, "must be second or minute") unless range

    errors.add(:rate_limit, "must be between #{range.first} and #{range.last} per #{rate_limit_period}") unless range.cover?(rate_limit)
  end
end
