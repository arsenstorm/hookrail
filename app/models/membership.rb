# One user's seat in one org. Owners and admins see every project; members see
# only what project_grants give them. The partial unique index keeps exactly
# one owner per org.
class Membership < ApplicationRecord
  belongs_to :organization
  belongs_to :user
  has_many :project_grants, dependent: :destroy

  enum :role, { owner: "owner", admin: "admin", member: "member" }

  def admin_or_owner? = owner? || admin?

  def accessible_projects
    return organization.projects.order(:id) if admin_or_owner?

    organization.projects.joins(:project_grants)
                .where(project_grants: { membership_id: id }).order(:id)
  end

  # The remembered project when it is still accessible, else the first
  # accessible one — the single fallback seam for stale/revoked choices.
  def current_project_or_default
    remembered = current_project_id && accessible_projects.find_by(id: current_project_id)
    remembered || accessible_projects.first
  end

  def can_view_project?(project)
    return false unless project
    return true if admin_or_owner?

    project_grants.exists?(project_id: project.id)
  end

  def can_edit_project?(project)
    return false unless project
    return true if admin_or_owner?

    project_grants.exists?(project_id: project.id, level: "editor")
  end

  # Demote self first so the one-owner-per-org index never sees two owners.
  def transfer_ownership!(to_membership)
    transaction do
      update!(role: :admin)
      to_membership.update!(role: :owner)
      organization.update!(owner_id: to_membership.user_id)
    end
  end
end
