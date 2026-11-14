# A session advisory lock per rider and integration. It serializes remote
# operations without keeping local transactions open across HTTP.
module OwnerLock
  def self.hold(user, integration)
    ApplicationRecord.connection_pool.with_connection do |connection|
      key = "hashtextextended(#{connection.quote("cyclefar-#{integration}-#{user.id}")}, 0)"
      connection.execute("SELECT pg_advisory_lock(#{key})")
      begin
        yield
      ensure
        connection.execute("SELECT pg_advisory_unlock(#{key})")
      end
    end
  end
end
