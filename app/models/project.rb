class Project < ApplicationRecord
  belongs_to :organization

  has_many :sources, dependent: :destroy
  has_many :destinations, dependent: :destroy
  has_many :connections, dependent: :destroy
  has_many :project_grants, dependent: :destroy
  has_many :issues, dependent: :destroy

  validates :name, presence: true
end
