class EventsController < ApplicationController
  def index
    @events = Event
      .joins(:source)
      .where(sources: { project_id: Current.project.id })
      .includes(:source, :attempts)
      .order(received_at: :desc)
      .limit(100)
  end

  def show
    @event = Event
      .joins(:source)
      .where(sources: { project_id: Current.project.id })
      .includes(attempts: { connection: [ :source, :destination ] })
      .find(params[:id])
  end
end
