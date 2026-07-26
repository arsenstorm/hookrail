# Liveness of `hookrail listen` sessions, tracked as cache-TTL heartbeats: no
# table and no sweeper — a dead CLI stops refreshing and the key expires.
class CliPresence
  TTL = 90.seconds

  def self.connect(connection_id) = beat(connection_id)

  def self.beat(connection_id) = Rails.cache.write(key(connection_id), true, expires_in: TTL)

  def self.disconnect(connection_id) = Rails.cache.delete(key(connection_id))

  def self.online?(connection_id) = Rails.cache.exist?(key(connection_id))

  def self.key(connection_id) = "cli_presence/#{connection_id}"
end
