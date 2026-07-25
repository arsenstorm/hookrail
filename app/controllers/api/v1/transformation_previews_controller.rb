module Api
  module V1
    class TransformationPreviewsController < BaseController
      # Runs a transform against a stored event and returns the output
      # without delivering anything. `code` previews unsaved edits; omitted,
      # the connection's saved transformation runs.
      def create
        connection = Current.project.connections.find(params[:id])
        event = Event.joins(:source)
                     .where(sources: { project_id: Current.project.id })
                     .find(params.require(:event_id))
        code = params[:code].presence || connection.transformation
        if code.blank?
          return render_error(:unprocessable_entity, "transformation_failed",
                              "no transformation code")
        end

        preview = Transformation::Runner.run(code, event)
        render json: { preview: { headers: preview[:headers], body: preview[:body] } }
      rescue Transformation::Error => e
        render_error :unprocessable_entity, "transformation_failed", e.message
      end
    end
  end
end
