class QuarantinedWebhooksController < ApplicationController
  def index
    @quarantined_webhooks = scope.includes(:source).order(received_at: :desc, id: :desc).limit(100)
  end

  def show
    @quarantined_webhook = scope.find(params[:id])
  end

  private

  # ponytail: cap at 100 newest, add pagination when someone actually pages
  def scope
    QuarantinedWebhook.joins(:source).where(sources: { project_id: Current.project.id })
  end
end
