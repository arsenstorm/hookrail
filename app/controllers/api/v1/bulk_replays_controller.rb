module Api
  module V1
    class BulkReplaysController < BaseController
      include EventFiltering

      # ponytail: enqueues in-request like bulk retry; move to a background job
      # if filtered sets grow past a few thousand events.
      def create
        set_event_filters
        connection = Current.project.connections.find(params[:connection_id])

        unless connection.status_active?
          return render_error(:unprocessable_entity, "connection_not_active",
                              "That connection is #{connection.status}.")
        end

        in_flight = Attempt.in_flight_event_ids(filtered_events, connection)
        enqueued = 0
        filtered_events.find_each do |event|
          next if in_flight.include?(event.id)
          next unless connection.routes?(event)

          enqueued += 1 if Attempt.claim_retry!(event_id: event.id, connection_id: connection.id, replay: true)
        end
        render json: { enqueued: enqueued }, status: :accepted
      end
    end
  end
end
