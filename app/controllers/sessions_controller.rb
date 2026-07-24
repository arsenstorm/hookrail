class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create failure]

  def new
  end

  def create
    user = User.from_omniauth(request.env["omniauth.auth"])
    reset_session
    session[:user_id] = user.id
    redirect_to root_path, notice: "Signed in as #{user.github_login}"
  end

  def destroy
    reset_session
    redirect_to login_path, notice: "Signed out"
  end

  def failure
    redirect_to login_path, alert: "Authentication failed"
  end
end
