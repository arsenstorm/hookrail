class Current < ActiveSupport::CurrentAttributes
  attribute :user, :organization, :project, :membership
end
