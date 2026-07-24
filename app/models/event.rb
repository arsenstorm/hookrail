class Event < ApplicationRecord
  belongs_to :source
  has_many :attempts, dependent: :destroy
end
