class IssuesController < ApplicationController
  before_action :require_project_access
  before_action :require_project_editor, only: %i[acknowledge resolve]

  STATUSES = %w[open acknowledged resolved].freeze

  def index
    @status = params[:status].presence
    @status = nil unless STATUSES.include?(@status) || @status == "all"

    scope = Current.project.issues.includes(:subject)
    scope = scope.unresolved if @status.nil?
    scope = scope.where(status: @status) if STATUSES.include?(@status)
    @issues = scope.order(last_seen_at: :desc)
  end

  def show
    @issue = Current.project.issues.find(params[:id])
  end

  # State guards keep the partial unique index honest: un-resolving a row
  # while a newer one is open would collide, so ack only moves open ->
  # acknowledged and resolve never runs twice.
  def acknowledge
    issue = Current.project.issues.find(params[:id])
    if issue.status_open?
      issue.update!(status: :acknowledged)
      redirect_to issues_path, notice: "Issue acknowledged."
    else
      redirect_to issues_path, alert: "Only open issues can be acknowledged."
    end
  end

  def resolve
    issue = Current.project.issues.find(params[:id])
    if issue.status_resolved?
      redirect_to issues_path, alert: "Issue is already resolved."
    else
      issue.update!(status: :resolved)
      redirect_to issues_path, notice: "Issue resolved."
    end
  end
end
