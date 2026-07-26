# One subscription per `hookrail listen` process, scoped to a connection whose
# destination is kind "cli". Subscription doubles as presence.
class CliChannel < ApplicationCable::Channel
  def subscribed
    conn = ::Connection.joins(:project)
                       .where(projects: { organization_id: cli_token.organization_id })
                       .find_by(id: params[:connection_id])
    # Same gate as the HTTP side: org membership alone is not project access.
    membership = Membership.find_by(user_id: cli_token.user_id,
                                    organization_id: cli_token.organization_id)
    return reject unless conn&.destination&.kind_cli? && membership&.can_view_project?(conn.project)

    @connection_id = conn.id
    stream_from "cli_connection_#{conn.id}"
    CliPresence.connect(conn.id)
  end

  def heartbeat(_data = {})
    CliPresence.beat(@connection_id) if @connection_id
  end

  def unsubscribed
    CliPresence.disconnect(@connection_id) if @connection_id
  end
end
