class ApiKeysController < ApplicationController
  before_action :require_org_admin

  def index
    @api_keys = Current.organization.api_keys.order(created_at: :desc)
    @cli_tokens = Current.organization.cli_tokens.active.includes(:user).order(created_at: :desc)
  end

  def create
    name = params.dig(:api_key, :name).presence || "API key"
    _key, raw = ApiKey.issue!(organization: Current.organization, name: name)
    # Shown once on the next page via flash, then gone — only the digest is stored.
    flash[:new_api_key] = raw
    redirect_to api_keys_path
  end

  # Revoke, don't delete: the row stays visible so operators can see what existed.
  def destroy
    Current.organization.api_keys.find(params[:id]).revoke!
    redirect_to api_keys_path, notice: "API key revoked."
  end
end
