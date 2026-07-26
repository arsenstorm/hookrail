module Api
  module V1
    module Cli
      # Find-or-create the CLI destination + connection for a source, so
      # `hookrail listen` is idempotent across reconnects. Editor role
      # required (enforced in BaseController: mutating + not self-service).
      class ListenersController < Api::V1::BaseController
        def create
          source = Current.project.sources.find(params.require(:source))
          destination = Current.project.destinations.kind_cli.find_or_create_by!(name: cli_destination_name)
          connection = ::Connection.find_or_create_by!(project: Current.project,
                                                       source: source, destination: destination)
          render json: {
            source: { id: source.id, name: source.name },
            destination_id: destination.id,
            connection_id: connection.id,
            websocket_url: request.base_url.sub(/\Ahttp/, "ws") + "/cable",
            subscription: { channel: "CliChannel", connection_id: connection.id }
          }, status: :created
        end

        private

        def cli_destination_name = "CLI (#{Current.user&.github_login || params[:device_name].presence || "device"})"
      end
    end
  end
end
