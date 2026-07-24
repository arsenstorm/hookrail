class Connection < ApplicationRecord
  belongs_to :source
  belongs_to :destination
  has_many :attempts, dependent: :destroy
end
