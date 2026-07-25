class InvitationsController < ApplicationController
  before_action :require_org_admin

  def create
    attrs = params.require(:invitation)
    invitation = Current.organization.invitations.new(email: attrs[:email], role: attrs[:role])
    if params[:invitation][:project_id].present? && %w[editor viewer].include?(params[:invitation][:level])
      invitation.grants = [ { "project_id" => params[:invitation][:project_id].to_i, "level" => params[:invitation][:level] } ]
    end
    if invitation.save
      redirect_to members_path, notice: "Invitation created — copy the link below and send it over."
    else
      redirect_to members_path, alert: invitation.errors.full_messages.to_sentence
    end
  end

  def destroy
    Current.organization.invitations.find(params[:id]).destroy!
    redirect_to members_path, notice: "Invitation revoked."
  end
end
