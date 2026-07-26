class AlertWebhooksController < ApplicationController
  before_action :require_org_admin

  def show
  end

  def update
    if Current.organization.update(params.require(:organization).permit(:alert_webhook_url, :slack_webhook_url, :discord_webhook_url))
      redirect_to alert_webhook_path, notice: "Alert webhook saved."
    else
      render :show, status: :unprocessable_entity
    end
  end

  # Clearing the URL clears the secret too — that lifecycle lives in the model.
  def destroy
    Current.organization.update!(alert_webhook_url: nil)
    redirect_to alert_webhook_path, notice: "Alert webhook removed."
  end

  def test
    if Current.organization.alert_webhook_configured? || Current.organization.chat_webhook_configured?
      Alerts.test(Current.organization)
      redirect_to alert_webhook_path, notice: "Test alert sent."
    else
      redirect_to alert_webhook_path, alert: "Configure a URL first."
    end
  end
end
