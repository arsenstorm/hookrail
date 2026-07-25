class Connection < ApplicationRecord
  belongs_to :project
  belongs_to :source
  belongs_to :destination
  has_many :attempts, dependent: :destroy

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
