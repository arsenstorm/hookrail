class RetentionsController < ApplicationController
  before_action :require_org_admin

  def show
  end

  def update
    if Current.organization.update(retention_days: params.require(:organization)[:retention_days])
      redirect_to retention_path, notice: "Retention saved."
    else
      render :show, status: :unprocessable_entity
    end
  end
end
