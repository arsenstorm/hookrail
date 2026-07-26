module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :cli_token

    def connect
      raw = request.headers["Authorization"].to_s.delete_prefix("Bearer").strip
      token = CliToken.authenticate(raw)
      # Same rule as the JSON API: a token whose user left the org is dead.
      unless token && Membership.exists?(user_id: token.user_id, organization_id: token.organization_id)
        reject_unauthorized_connection
      end
      self.cli_token = token
    end
  end
end
