module Api
  module V1
    class AlertWebhooksController < BaseController
      # Org-wide alerting, and `show` hands back the signing secret — both need
      # an org role, matching require_org_admin on the web controller.
      before_action :require_org_admin!

      # The secret is returned here, unlike destination signing secrets:
      # receivers are configured by the same operator who reads this endpoint,
      # and the UI shows it alongside the URL for the same reason.
      def show = render_alert_webhook

      def update
        if Current.organization.update(alert_webhook_url: params.require(:alert_webhook)[:url])
          render_alert_webhook
        else
          render_validation_error(Current.organization)
        end
      end

      def destroy
        Current.organization.update!(alert_webhook_url: nil)
        head :no_content
      end

      private

      def render_alert_webhook
        render json: { alert_webhook: { url: Current.organization.alert_webhook_url,
                                        secret: Current.organization.alert_webhook_secret } }
      end
    end
  end
end
