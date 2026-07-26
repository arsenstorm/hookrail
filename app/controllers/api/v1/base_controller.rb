module Api
  module V1
    class BaseController < ActionController::API
      before_action :authenticate!

      rescue_from ActiveRecord::RecordNotFound do
        render_error :not_found, "not_found", "Resource not found"
      end

      rescue_from ActionController::ParameterMissing do |e|
        render_error :bad_request, "bad_request", e.message
      end

      private

      # Bearer credential -> org -> its (single) project. Two credential kinds:
      # org-wide "hk_" API keys (admin-issued, full access) and per-user "hkc_"
      # CLI tokens (device-flow issued, enforce the user's project role).
      # Revoked/unknown credentials all read as invalid, and other orgs'
      # resource ids 404, so existence is never leaked.
      def authenticate!
        raw = request.authorization.to_s.delete_prefix("Bearer").strip
        return authenticate_cli_token!(raw) if raw.start_with?("hkc_")

        api_key = ApiKey.authenticate(raw)
        return render_error(:unauthorized, "unauthorized", "Invalid or missing API key") unless api_key

        Current.organization = api_key.organization
        Current.project = api_key.organization.projects.first
      end

      def authenticate_cli_token!(raw)
        token = CliToken.authenticate(raw)
        membership = token && Membership.find_by(user_id: token.user_id, organization_id: token.organization_id)
        return render_error(:unauthorized, "unauthorized", "Invalid or revoked CLI token") unless membership

        @cli_token = token
        Current.user = token.user
        Current.membership = membership
        Current.organization = token.organization
        Current.project = token.organization.projects.first
        token.touch_last_used!

        # A token is only as strong as its user's role: no project access -> no
        # reads; no editor rights -> no writes.
        unless cli_self_service_request?
          unless membership.can_view_project?(Current.project)
            return render_error(:forbidden, "forbidden", "You don't have access to this project")
          end
          unless request.get? || membership.can_edit_project?(Current.project)
            render_error(:forbidden, "forbidden", "Your role is read-only for this project")
          end
        end
      end

      # whoami/token are self-service: reading your own identity or revoking
      # your own token is always allowed, independent of project role. Exact
      # paths, not the whole /api/v1/cli/ namespace — other CLI endpoints
      # (listeners, attempt results) must still pass the role checks.
      def cli_self_service_request? = [ "/api/v1/cli/whoami", "/api/v1/cli/token" ].include?(request.path)

      def render_error(status, code, message)
        render json: { error: { code: code, message: message } }, status: status
      end

      def render_validation_error(record)
        render json: { error: { code: "validation_failed",
                                message: record.errors.full_messages.to_sentence } },
               status: :unprocessable_entity
      end
    end
  end
end
