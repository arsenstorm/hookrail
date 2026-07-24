class User < ApplicationRecord
  has_one :organization, foreign_key: :owner_id, inverse_of: :owner, dependent: :destroy

  validates :github_uid, presence: true, uniqueness: true

  # Find-or-create a user from a GitHub OmniAuth payload, ensuring the personal
  # organization and its default project exist. Idempotent per github_uid.
  def self.from_omniauth(auth)
    user = find_or_initialize_by(github_uid: auth.uid.to_s)
    user.github_login = auth.info.nickname
    user.name         = auth.info.name
    user.email        = auth.info.email
    user.avatar_url   = auth.info.image
    user.save!
    user.ensure_org_and_project!
    user
  end

  # ponytail: single-user personal org; DB unique index on owner_id guards dup orgs.
  def ensure_org_and_project!
    org = organization || create_organization!(name: github_login.presence || "personal")
    org.projects.first || org.projects.create!(name: "Default")
    org
  end
end
