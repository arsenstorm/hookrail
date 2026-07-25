module Api
  module V1
    class DestinationsController < BaseController
      def index = render json: { destinations: scope.order(:name).map { |d| destination_json(d) } }

      def show = render json: { destination: destination_json(scope.find(params[:id])) }

      def create
        destination = Current.project.destinations.new(destination_params)
        if destination.save
          render json: { destination: destination_json(destination) }, status: :created
        else
          render_validation_error(destination)
        end
      end

      def update
        destination = scope.find(params[:id])
        if destination.update(destination_params)
          render json: { destination: destination_json(destination) }
        else
          render_validation_error(destination)
        end
      end

      def destroy
        scope.find(params[:id]).destroy!
        head :no_content
      end

      private

      def scope = Current.project.destinations

      def destination_params
        params.require(:destination).permit(:name, :url, :rate_limit, :rate_limit_period, headers: {})
      end

      def destination_json(destination)
        destination.as_json(only: %i[id name url rate_limit rate_limit_period headers created_at updated_at])
      end
    end
  end
end
