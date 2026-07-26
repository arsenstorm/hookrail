class CliTokensController < ApplicationController
  before_action :require_org_admin

  # Revoke, don't delete: mirrors ApiKeysController#destroy.
  def destroy
    Current.organization.cli_tokens.find(params[:id]).revoke!
    redirect_to api_keys_path, notice: "CLI token revoked."
  end
end
