class User < ApplicationRecord
  has_one :organization, foreign_key: :owner_id, inverse_of: :owner, dependent: :destroy
  has_many :memberships, dependent: :destroy
  has_many :cli_tokens, dependent: :destroy

  validates :github_uid, presence: true, uniqueness: true

  # Ties issued session cookies to something revocable server-side: rotate it
  # and every cookie carrying the old value stops authenticating.
  has_secure_token :session_token

  def rotate_session_token! = regenerate_session_token

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

  # ponytail: personal org bootstrap on sign-in; memberships are the access truth.
  def ensure_org_and_project!
    org = organization || memberships.order(:created_at).first&.organization ||
          create_organization!(name: github_login.presence || "personal")
    Membership.find_or_create_by!(organization: org, user: self) do |m|
      m.role = org.memberships.exists?(role: "owner") ? "member" : "owner"
    end
    org.projects.first || org.projects.create!(name: "Default")
    org
  end
end
