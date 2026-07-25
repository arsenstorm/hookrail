module Api
  module V1
    class AttemptsController < BaseController
      def index
        event = Event.joins(:source).where(sources: { project_id: Current.project.id }).find(params[:event_id])
        render json: { attempts: event.attempts.order(:connection_id, :attempt_number).map { |a| attempt_json(a) } }
      end

      private

      def attempt_json(attempt)
        attempt.as_json(only: %i[id event_id connection_id attempt_number status response_status
                                  response_body error duration_ms attempted_at])
      end
    end
  end
end
