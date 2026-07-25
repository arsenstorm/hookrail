class Connection < ApplicationRecord
  belongs_to :project
  belongs_to :source
  belongs_to :destination
  has_many :attempts, dependent: :destroy

  UNHEALTHY_THRESHOLD = 5

  scope :unhealthy, -> { where.not(unhealthy_since: nil) }

  def unhealthy? = unhealthy_since.present?

  # Counters and state flips are single atomic UPDATEs so concurrent delivery
  # jobs can't double-send an alert: whichever job's guarded UPDATE matches a
  # row "claims" the transition and enqueues the one email.
  def record_delivery_failure
    self.class.update_counters(id, consecutive_failures: 1)
    claimed = self.class.where(id: id, unhealthy_since: nil)
                  .where(consecutive_failures: UNHEALTHY_THRESHOLD..)
                  .update_all(unhealthy_since: Time.current)
    AlertMailer.connection_unhealthy(reload).deliver_later if claimed == 1
  end

  def record_delivery_success
    recovered = self.class.where(id: id).where.not(unhealthy_since: nil)
                    .update_all(unhealthy_since: nil, consecutive_failures: 0)
    if recovered == 1
      AlertMailer.connection_recovered(reload).deliver_later
    else
      self.class.where(id: id).update_all(consecutive_failures: 0)
    end
  end

  # Mirrors the unique (source_id, destination_id) DB index so a duplicate pair
  # re-renders the form with a 422 instead of raising RecordNotUnique / 500.
  validates :source_id, uniqueness: { scope: :destination_id,
            message: "is already connected to that destination" }

  # belongs_to only checks the source/destination exist, not that they are the
  # caller's. Block wiring a connection to another project's endpoints so a
  # crafted source_id/destination_id can't cross project boundaries.
  validate :endpoints_belong_to_project

  private

  def endpoints_belong_to_project
    errors.add(:source, "must belong to this project") if source && source.project_id != project_id
    errors.add(:destination, "must belong to this project") if destination && destination.project_id != project_id
  end
end
