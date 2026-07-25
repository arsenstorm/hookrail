class BulkRetriesController < ApplicationController
  include EventFiltering

  before_action :require_project_editor

  # ponytail: claims run in-request, two queries per pair; move to a background
  # job if filtered sets grow past a few thousand deliveries.
  def create
    set_event_filters
    pairs = Attempt.retryable_for(filtered_events).pluck(:event_id, :connection_id)
    enqueued = pairs.count do |event_id, connection_id|
      Attempt.claim_retry!(event_id: event_id, connection_id: connection_id)
    end
    redirect_to events_path(@filter_params), notice: "Retrying #{enqueued} #{"delivery".pluralize(enqueued)}."
  end
end
