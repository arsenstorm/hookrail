class Attempt < ApplicationRecord
  belongs_to :event
  belongs_to :connection

  enum :status, {
    pending: "pending",
    delivering: "delivering",
    succeeded: "succeeded",
    failed: "failed",
    dead: "dead"
  }
end
