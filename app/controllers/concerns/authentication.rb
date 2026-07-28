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
    # The cookie must still match the user's current session token, so signing
    # out invalidates copies of the cookie we will never see again.
    return unless session[:session_token].present? &&
                  ActiveSupport::SecurityUtils.secure_compare(
                    session[:session_token].to_s, user.session_token.to_s
                  )

    Current.user = user
    # The session may name an org; it counts only if a membership backs it.
    # Fallback: oldest membership, which is the personal org for most users.
    membership = user.memberships.includes(:organization)
                     .find_by(organization_id: session[:organization_id]) ||
                 user.memberships.includes(:organization).order(:created_at).first
    Current.membership = membership
    Current.organization = membership&.organization
    Current.project = membership&.current_project_or_default
    user
  end

  def current_user
    Current.user
  end

  def request_authentication
    redirect_to sign_in_path
  end
end
