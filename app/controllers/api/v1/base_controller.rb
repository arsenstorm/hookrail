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

      # Bearer key -> org -> its (single) project, mirroring session auth in
      # Authentication#resume_session. Revoked keys read the same as invalid
      # ones, and other orgs' resource ids 404, so existence is never leaked.
      def authenticate!
        raw = request.authorization.to_s.delete_prefix("Bearer").strip
        api_key = ApiKey.authenticate(raw)
        return render_error(:unauthorized, "unauthorized", "Invalid or missing API key") unless api_key

        Current.organization = api_key.organization
        Current.project = api_key.organization.projects.first
      end

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
