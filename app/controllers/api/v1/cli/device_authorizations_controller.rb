module Api
  module V1
    module Cli
      # Unauthenticated: this is how the CLI gets a credential in the first
      # place, so it can't require one.
      class DeviceAuthorizationsController < Api::V1::BaseController
        skip_before_action :authenticate!, only: %i[create token]

        def create
          device_name = (params[:device_name].presence || "unknown device").to_s.first(80)
          record, raw = CliAuthorization.start!(device_name: device_name)
          render json: {
            device_code: raw,
            user_code: record.user_code,
            verification_url: "#{request.base_url}/cli/authorize?code=#{record.user_code}",
            expires_in: CliAuthorization::TTL.to_i,
            interval: 5
          }, status: :created
        end

        def token
          result = CliAuthorization.claim_token!(params.require(:device_code))
          case result
          when :pending
            render json: { status: "pending" }, status: :accepted
          when :gone
            render_error(:gone, "authorization_gone", "That authorization is invalid, expired, or was denied.")
          else
            token, raw = result
            render json: { token: raw, organization: { id: token.organization_id, name: token.organization.name } }
          end
        end
      end
    end
  end
end
