# A pending seat: accepting creates the membership and destroys the row, so
# every surviving invitation is by definition still pending.
class Invitation < ApplicationRecord
  EXPIRY = 7.days

  belongs_to :organization

  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :role, inclusion: { in: %w[admin member] }

  before_create { self.token = SecureRandom.urlsafe_base64(24) }

  def expired? = created_at <= EXPIRY.ago

  # Returns the membership on success, or :expired / :email_mismatch.
  # The email must match the GitHub account's — a forwarded link is useless.
  def accept!(user)
    return :expired if expired?
    return :email_mismatch unless user.email.present? && user.email.casecmp?(email)

    membership = nil
    transaction do
      membership = organization.memberships.where(user: user).first_or_create!(role: role)
      Array(grants).each do |g|
        project = organization.projects.find_by(id: g["project_id"])
        next unless project

        membership.project_grants.find_or_create_by!(project: project) { |pg| pg.level = g["level"] }
      end
      destroy!
    end
    membership
  end
end
