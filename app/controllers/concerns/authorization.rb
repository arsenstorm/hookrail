# Server-side role checks. Hiding a button is not enforcement; every mutating
# controller declares one of these and the redirect is the contract.
module Authorization
  extend ActiveSupport::Concern

  private

  def require_project_access
    deny unless Current.project
  end

  def require_project_editor
    deny unless Current.membership&.can_edit_project?(Current.project)
  end

  def require_org_admin
    deny unless Current.membership&.admin_or_owner?
  end

  def require_owner
    deny unless Current.membership&.owner?
  end

  def deny
    redirect_to dashboard_path, alert: "You don't have permission to do that.", status: :see_other
  end
end
