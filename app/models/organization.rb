class Organization < ApplicationRecord
  belongs_to :owner, class_name: "User"
  has_many :projects, dependent: :destroy
  has_many :api_keys, dependent: :destroy

  validates :name, presence: true
end
