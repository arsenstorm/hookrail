class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create failure]

  def new
  end

  def create
    invite_token = session[:invite_token]
    user = User.from_omniauth(request.env["omniauth.auth"])
    reset_session
    session[:user_id] = user.id
    session[:session_token] = user.session_token
    # A parked invite goes to its confirmation screen rather than being accepted
    # here: signing in is consent to sign in, not to join someone's organization.
    return redirect_to(invite_path(invite_token)) if invite_token && Invitation.exists?(token: invite_token)

    redirect_to dashboard_path, notice: "Signed in as #{user.github_login}"
  end

  # Rotating the token invalidates every cookie issued to this user, not just
  # the one in this browser. That is the point: a cookie copied off a shared
  # machine is exactly what signing out should revoke, and we cannot tell the
  # copies apart. The cost is that signing out signs out your other devices.
  def destroy
    Current.user&.rotate_session_token!
    reset_session
    redirect_to sign_in_path, notice: "Signed out"
  end

  def failure
    redirect_to sign_in_path, alert: "Authentication failed"
  end
end
