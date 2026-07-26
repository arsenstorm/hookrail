module Api
  module V1
    module Cli
      # The CLI reports what happened after forwarding an event to localhost.
      # The guarded UPDATE races CliAttemptTimeoutJob: one finalizer wins,
      # repeats and losers read back the already-final status.
      class AttemptResultsController < Api::V1::BaseController
        MAX_BODY_EXCERPT = 10_000

        def create
          attempt = Attempt.joins(connection: :project)
                           .where(projects: { id: Current.project.id })
                           .find(params[:attempt_id])
          return render json: { status: attempt.status } unless attempt.delivering?

          success = params[:status].to_i.between?(200, 299)
          claimed = Attempt.where(id: attempt.id, status: "delivering")
                           .update_all(status: success ? "succeeded" : "failed",
                                       response_status: params[:status].presence,
                                       response_body: scrub(params[:body_excerpt].to_s.first(MAX_BODY_EXCERPT)),
                                       error: success ? nil : scrub(params[:error].to_s),
                                       duration_ms: params[:duration_ms].presence,
                                       updated_at: Time.current)
          return render json: { status: attempt.reload.status } unless claimed == 1

          attempt.reload
          if success
            attempt.connection.record_delivery_success
          else
            attempt.connection.record_delivery_failure
            DeliverEventJob.retry_or_bury(attempt.event, attempt.connection, attempt.replay,
                                          params[:retry_count].to_i)
          end
          render json: { status: attempt.status }
        end

        private

        # update_all skips the model's `normalizes`, so wire data is scrubbed
        # here or Postgres rejects \0 bytes at write time.
        def scrub(text) = ApplicationRecord::DB_TEXT.call(text).presence
      end
    end
  end
end
