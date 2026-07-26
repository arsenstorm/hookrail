module Api
  module V1
    module Cli
      class SessionsController < Api::V1::BaseController
        def whoami
          render json: {
            user: Current.user && { github_login: Current.user.github_login, name: Current.user.name },
            organization: { id: Current.organization.id, name: Current.organization.name },
            token: token_info
          }
        end

        # Self-revoke: only meaningful for CLI tokens, never for API keys.
        def destroy
          return render_error(:bad_request, "bad_request", "Not a CLI token.") unless @cli_token

          @cli_token.revoke!
          head :no_content
        end

        private

        def token_info
          @cli_token ? { kind: "cli", prefix: @cli_token.prefix, name: @cli_token.name } : { kind: "api_key" }
        end
      end
    end
  end
end
