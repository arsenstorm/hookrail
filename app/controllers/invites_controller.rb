# Public landing for invite links. Signed-in users accept immediately; everyone
# else parks the token in the session and picks it up after GitHub sign-in.
class InvitesController < ApplicationController
  allow_unauthenticated_access only: :show

  def show
    invitation = Invitation.find_by(token: params[:token])
    user = resume_session

    unless invitation
      return redirect_to(user ? root_path : login_path, alert: "That invitation is no longer valid.")
    end

    if user
      case (result = invitation.accept!(user))
      when Membership
        session[:organization_id] = result.organization_id
        redirect_to root_path, notice: "Joined #{result.organization.name}."
      when :expired
        redirect_to root_path, alert: "That invitation has expired."
      when :email_mismatch
        redirect_to root_path, alert: "That invitation was issued to a different email address."
      end
    else
      session[:invite_token] = params[:token]
      redirect_to login_path, notice: "Sign in with GitHub to accept your invitation to #{invitation.organization.name}."
    end
  end
end
