class OrganizationsController < ApplicationController
  def new
    @organization = Organization.new
  end

  # Same bootstrap as the personal org in User#ensure_org_and_project!: owner
  # membership plus a Default project, then switch the session to it.
  def create
    @organization = Organization.new(organization_params.merge(owner: Current.user))
    if @organization.save
      Membership.create!(organization: @organization, user: Current.user, role: :owner)
      @organization.projects.create!(name: "Default")
      session[:organization_id] = @organization.id
      redirect_to dashboard_path, notice: "Organization created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def organization_params
    params.require(:organization).permit(:name)
  end
end
