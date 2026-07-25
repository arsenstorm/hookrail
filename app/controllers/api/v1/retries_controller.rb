module Api
  module V1
    class RetriesController < BaseController
      def create
        event = Event.joins(:source).where(sources: { project_id: Current.project.id }).find(params[:event_id])
        connection = event.source.connections.find(params[:connection_id])

        latest = Attempt.where(event: event, connection: connection).order(:attempt_number).last
        unless latest && (latest.dead? || latest.failed?)
          return render_error(:unprocessable_entity, "not_retryable", "That delivery can't be retried.")
        end

        Attempt.claim_retry!(event_id: event.id, connection_id: connection.id)
        render json: { status: "retrying" }, status: :accepted
      end
    end
  end
end
