module Api
  module V1
    class RetentionsController < BaseController
      # Retention is org-wide, and shrinking it deletes history across every
      # project in the org — the web controller gates this behind
      # require_org_admin, and this one drifted from it.
      before_action :require_org_admin!

      def show = render_retention

      def update
        if Current.organization.update(retention_days: params.require(:retention)[:days])
          render_retention
        else
          render_validation_error(Current.organization)
        end
      end

      private

      def render_retention
        render json: { retention: { days: Current.organization.retention_days } }
      end
    end
  end
end
