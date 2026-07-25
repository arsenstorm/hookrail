class AddAlertWebhookToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :alert_webhook_url, :string
    add_column :organizations, :alert_webhook_secret, :string
  end
end
