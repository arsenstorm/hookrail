class ProjectsController < ApplicationController
  before_action :require_org_admin

  def index
    @projects = Current.organization.projects.order(:id)
  end

  def create
    project = Current.organization.projects.new(project_params)
    if project.save
      redirect_to projects_path, notice: "Project created."
    else
      redirect_to projects_path, alert: project.errors.full_messages.to_sentence
    end
  end

  def update
    project = Current.organization.projects.find(params[:id])
    if project.update(project_params)
      redirect_to projects_path, notice: "Project renamed."
    else
      redirect_to projects_path, alert: project.errors.full_messages.to_sentence
    end
  end

  def destroy
    project = Current.organization.projects.find(params[:id])
    if project.destroy
      redirect_to projects_path, notice: "Project deleted."
    else
      redirect_to projects_path, alert: project.errors.full_messages.to_sentence
    end
  end

  private

  def project_params
    params.require(:project).permit(:name)
  end
end
