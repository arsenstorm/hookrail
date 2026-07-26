class CliTokensController < ApplicationController
  before_action :set_token
  # Admins revoke anyone's token from the API keys page; everyone can revoke
  # their own from their security page.
  before_action :require_org_admin, unless: -> { @token.user_id == Current.user.id }

  # Revoke, don't delete: mirrors ApiKeysController#destroy.
  def destroy
    @token.revoke!
    fallback = @token.user_id == Current.user.id ? security_account_path : api_keys_path
    redirect_back fallback_location: fallback, notice: "CLI token revoked."
  end

  private

  def set_token
    @token = Current.organization.cli_tokens.find(params[:id])
  end
end
