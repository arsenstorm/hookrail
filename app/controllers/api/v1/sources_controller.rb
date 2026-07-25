module Api
  module V1
    class SourcesController < BaseController
      def index = render json: { sources: scope.order(:name).map { |s| source_json(s) } }

      def show = render json: { source: source_json(scope.find(params[:id])) }

      def create
        source = Current.project.sources.new(source_params)
        if source.save
          render json: { source: source_json(source) }, status: :created
        else
          render_validation_error(source)
        end
      end

      def update
        source = scope.find(params[:id])
        if source.update(source_params)
          render json: { source: source_json(source) }
        else
          render_validation_error(source)
        end
      end

      def destroy
        scope.find(params[:id]).destroy!
        head :no_content
      end

      private

      def scope = Current.project.sources

      def source_params
        params.require(:source).permit(:name, :verification_secret, :verification_header,
          :verification_algorithm, :verification_encoding, :verification_header_format,
          :verification_signature_prefix, :verification_signature_key, :verification_timestamp_key,
          :verification_timestamp_header, :verification_payload_template, :verification_tolerance_seconds)
      end

      # The verification config holds the signing secret — never serialize it.
      def source_json(source)
        source.as_json(only: %i[id name token created_at updated_at])
              .merge("verification_enabled" => source.verification_enabled?)
      end
    end
  end
end
