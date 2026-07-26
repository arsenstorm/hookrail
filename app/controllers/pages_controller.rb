class PagesController < ApplicationController
  allow_unauthenticated_access

  # Authentication is skipped, but the session still decides which CTA renders,
  # so the session is resumed anyway. Signed-in visitors stay on the page.
  before_action :resume_session

  layout "marketing"

  def home
  end
end
