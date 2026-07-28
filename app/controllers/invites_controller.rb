# Public landing for invite links. Signed-in users get a confirmation screen;
# everyone else parks the token in the session and picks it up after GitHub
# sign-in. Accepting is a POST: joining an organization also switches the
# user's active org, so a bare link must never do it — anyone who can get a
# victim to follow a URL could otherwise move their next sources, destinations,
# and API keys into an org the sender controls.
class InvitesController < ApplicationController
  allow_unauthenticated_access only: :show
  before_action :load_invitation

  def show
    return if resume_session

    session[:invite_token] = params[:token]
    redirect_to sign_in_path,
      notice: "Sign in with GitHub to accept your invitation to #{@invitation.organization.name}."
  end

  def create
    case (result = @invitation.accept!(Current.user))
    when Membership
      session[:organization_id] = result.organization_id
      redirect_to dashboard_path, notice: "Joined #{result.organization.name}."
    when :expired
      redirect_to dashboard_path, alert: "That invitation has expired."
    when :email_mismatch
      redirect_to dashboard_path, alert: "That invitation was issued to a different email address."
    end
  end

  private

  def load_invitation
    @invitation = Invitation.find_by(token: params[:token])
    return if @invitation

    redirect_to(Current.user ? dashboard_path : sign_in_path,
                alert: "That invitation is no longer valid.")
  end
end
