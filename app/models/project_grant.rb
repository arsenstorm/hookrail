class ProjectGrant < ApplicationRecord
  belongs_to :membership
  belongs_to :project

  validates :level, inclusion: { in: %w[editor viewer] }
end
