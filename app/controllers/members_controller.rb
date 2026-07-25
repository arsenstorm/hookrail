class MembersController < ApplicationController
  before_action :require_org_admin
  before_action :require_owner, only: :transfer_ownership

  def index
    @memberships = Current.organization.memberships.includes(:user, :project_grants).order(:created_at)
    @invitations = Current.organization.invitations.order(:created_at)
    @projects = Current.organization.projects.order(:id)
  end

  def update
    membership = Current.organization.memberships.find(params[:id])
    return redirect_to members_path, alert: "The owner's role changes only by ownership transfer." if membership.owner?

    membership.transaction do
      role = params.dig(:membership, :role)
      membership.update!(role: role) if %w[admin member].include?(role)
      (params.dig(:membership, :grants) || {}).each do |project_id, level|
        project = Current.organization.projects.find_by(id: project_id)
        next unless project

        existing = membership.project_grants.find_by(project: project)
        if %w[editor viewer].include?(level)
          existing ? existing.update!(level: level) : membership.project_grants.create!(project: project, level: level)
        else
          existing&.destroy!
        end
      end
    end
    redirect_to members_path, notice: "Member updated."
  end

  def destroy
    membership = Current.organization.memberships.find(params[:id])
    return redirect_to members_path, alert: "Transfer ownership before removing the owner." if membership.owner?
    return redirect_to members_path, alert: "You can't remove yourself." if membership.user_id == Current.user.id

    membership.destroy!
    redirect_to members_path, notice: "Member removed."
  end

  def transfer_ownership
    target = Current.organization.memberships.find(params[:id])
    return redirect_to members_path, alert: "You already own this org." if target.id == Current.membership.id

    Current.membership.transfer_ownership!(target)
    redirect_to members_path, notice: "Ownership transferred."
  end
end
