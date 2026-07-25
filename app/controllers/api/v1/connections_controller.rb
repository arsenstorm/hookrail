module Api
  module V1
    class ConnectionsController < BaseController
      def index = render json: { connections: scope.order(created_at: :desc).map { |c| connection_json(c) } }

      def show = render json: { connection: connection_json(scope.find(params[:id])) }

      def create
        connection = Current.project.connections.new(connection_params)
        if connection.save
          render json: { connection: connection_json(connection) }, status: :created
        else
          render_validation_error(connection)
        end
      end

      def update
        connection = scope.find(params[:id])
        if connection.update(connection_params)
          render json: { connection: connection_json(connection) }
        else
          render_validation_error(connection)
        end
      end

      def destroy
        scope.find(params[:id]).destroy!
        head :no_content
      end

      private

      def scope = Current.project.connections

      # Re-resolve foreign ids through the caller's project so another org's
      # source/destination id fails identically to a nonexistent one.
      def connection_params
        raw = params.require(:connection).permit(:source_id, :destination_id, :status, :transformation, retry_policy: {}, routing_rule: {})
        raw[:source_id] = Current.project.sources.where(id: raw[:source_id]).pick(:id) if raw.key?(:source_id)
        raw[:destination_id] = Current.project.destinations.where(id: raw[:destination_id]).pick(:id) if raw.key?(:destination_id)
        raw
      end

      def connection_json(connection)
        connection.as_json(only: %i[id source_id destination_id status consecutive_failures
                                     unhealthy_since routing_rule transformation retry_policy created_at updated_at])
      end
    end
  end
end
