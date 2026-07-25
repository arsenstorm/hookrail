module Api
  module V1
    class EventsController < BaseController
      include EventFiltering

      PAGE_SIZE = 50

      def index
        set_event_filters
        scope = filtered_events.order(received_at: :desc, id: :desc)
        if (cursor = decode_cursor(params[:cursor]))
          scope = scope.before_cursor(cursor[:received_at], cursor[:id])
        end
        rows        = scope.limit(PAGE_SIZE + 1).to_a
        events      = rows.first(PAGE_SIZE)
        next_cursor = rows.size > PAGE_SIZE ? encode_cursor(events.last) : nil
        render json: { events: events.map { |e| event_json(e) }, next_cursor: next_cursor }
      end

      def show
        event = Event.joins(:source).where(sources: { project_id: Current.project.id }).find(params[:id])
        render json: { event: event_json(event) }
      end

      private

      def event_json(event)
        event.as_json(only: %i[id source_id http_method path query_string headers body received_at])
      end
    end
  end
end
