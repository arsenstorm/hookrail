module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :current_user
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private

  def require_authentication
    resume_session || request_authentication
  end

  def resume_session
    user_id = session[:user_id]
    return unless user_id

    user = User.find_by(id: user_id)
    return unless user

    Current.user = user
    Current.organization = user.organization
    Current.project = user.organization&.projects&.first
    user
  end

  def current_user
    Current.user
  end

  def request_authentication
    redirect_to login_path
  end
end
