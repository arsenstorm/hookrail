module Api
  module V1
    class BulkRetriesController < BaseController
      include EventFiltering

      def create
        set_event_filters
        pairs = Attempt.retryable_for(filtered_events).pluck(:event_id, :connection_id)
        enqueued = pairs.count do |event_id, connection_id|
          Attempt.claim_retry!(event_id: event_id, connection_id: connection_id)
        end
        render json: { enqueued: enqueued }, status: :accepted
      end
    end
  end
end
