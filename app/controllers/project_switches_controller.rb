class ProjectSwitchesController < ApplicationController
  # find against accessible_projects doubles as the authorization check: a
  # project outside the caller's grants 404s instead of switching.
  def create
    project = Current.membership.accessible_projects.find(params[:id])
    Current.membership.update!(current_project_id: project.id)
    redirect_to dashboard_path
  end
end
