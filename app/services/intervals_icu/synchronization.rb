module IntervalsIcu
  module Synchronization
    def self.with_owner_lock(user)
      # A session advisory lock serializes remote operations without keeping
      # sync's local transactions open across HTTP. Retry identities must be
      # committed before upload, even if the process stops during the request.
      ApplicationRecord.connection_pool.with_connection do |connection|
        key = "hashtextextended(#{connection.quote("cyclefar-intervals-icu-#{user.id}")}, 0)"
        connection.execute("SELECT pg_advisory_lock(#{key})")
        begin
          yield
        ensure
          connection.execute("SELECT pg_advisory_unlock(#{key})")
        end
      end
    end
  end
end
