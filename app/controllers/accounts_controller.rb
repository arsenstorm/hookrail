class AccountsController < ApplicationController
  def show
    @memberships = Current.user.memberships.includes(:organization).order(:created_at)
  end

  def security
    # Org-scoped so the existing CliTokens#destroy (which finds through the
    # current org) can revoke straight from this page.
    @cli_tokens = Current.organization&.cli_tokens&.active&.where(user: Current.user)
                         &.order(created_at: :desc) || CliToken.none
  end
end
