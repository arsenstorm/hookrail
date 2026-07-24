class Source < ApplicationRecord
  has_many :events, dependent: :destroy
  has_many :connections, dependent: :destroy

  validates :name, presence: true

  # Generates a unique 24-char token in before_create; DB unique index enforces integrity.
  has_secure_token :token
end
