class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create failure]

  def new
  end

  def create
    invite_token = session[:invite_token]
    user = User.from_omniauth(request.env["omniauth.auth"])
    reset_session
    session[:user_id] = user.id
    if invite_token && (invitation = Invitation.find_by(token: invite_token))
      case (result = invitation.accept!(user))
      when Membership
        session[:organization_id] = result.organization_id
        return redirect_to dashboard_path, notice: "Joined #{result.organization.name}."
      when :expired
        return redirect_to dashboard_path, alert: "That invitation has expired."
      when :email_mismatch
        return redirect_to dashboard_path, alert: "That invitation was issued to a different email address."
      end
    end
    redirect_to dashboard_path, notice: "Signed in as #{user.github_login}"
  end

  def destroy
    reset_session
    redirect_to sign_in_path, notice: "Signed out"
  end

  def failure
    redirect_to sign_in_path, alert: "Authentication failed"
  end
end
