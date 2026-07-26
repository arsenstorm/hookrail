class OrgSwitchesController < ApplicationController
  def create
    membership = Current.user.memberships.find_by!(organization_id: params[:id])
    session[:organization_id] = membership.organization_id
    redirect_to dashboard_path
  end
end
