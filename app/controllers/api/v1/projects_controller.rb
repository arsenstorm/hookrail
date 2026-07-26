module Api
  module V1
    class ProjectsController < BaseController
      # Org-wide keys see every project; CLI tokens see what their user sees.
      def index
        scope = Current.membership ? Current.membership.accessible_projects : Current.organization.projects.order(:id)
        render json: { projects: scope.map { |p| p.as_json(only: %i[id name]) } }
      end
    end
  end
end
