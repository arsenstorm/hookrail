class Destination < ApplicationRecord
  has_many :connections, dependent: :destroy

  validates :name, presence: true
  validates :url, presence: true

  # Secret used to HMAC-sign forwarded payloads; auto-generated, DB unique index enforces integrity.
  has_secure_token :signing_secret
end
