class CliAuthorizationsController < ApplicationController
  def show
    @code = params[:code].to_s
    if @code.present?
      @authorization = CliAuthorization.pending.where("expires_at > ?", Time.current)
                                        .find_by(user_code: CliAuthorization.normalize_code(@code))
    end
  end

  def create
    authorization = CliAuthorization.pending.where("expires_at > ?", Time.current)
                                     .find_by(user_code: CliAuthorization.normalize_code(params[:code]))
    return redirect_to cli_authorize_path, alert: "That code is invalid or expired." unless authorization

    if params[:decision] == "deny"
      authorization.update!(status: :denied)
      redirect_to dashboard_path, notice: "CLI access denied."
    else
      authorization.update!(status: :approved, user: Current.user, organization: Current.organization)
      redirect_to dashboard_path, notice: "CLI authorized for #{Current.organization.name}. Return to your terminal."
    end
  end
end
