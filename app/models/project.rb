class Project < ApplicationRecord
  belongs_to :organization

  has_many :sources, dependent: :destroy
  has_many :destinations, dependent: :destroy
  has_many :connections, dependent: :destroy
  has_many :project_grants, dependent: :destroy
  has_many :issues, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :organization_id, case_sensitive: false }

  before_destroy :ensure_not_last_project

  private

  # ponytail: racing deletes could still empty an org; acceptable at this scale.
  def ensure_not_last_project
    # An org being destroyed takes all its projects with it — the guard only
    # blocks direct deletes, never the cascade.
    return if destroyed_by_association
    return if organization.projects.where.not(id: id).exists?

    errors.add(:base, "The last project in an organization can't be deleted")
    throw :abort
  end
end
