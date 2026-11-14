module IntervalsIcu
  module Synchronization
    # Serializes a rider's syncs. Retry identities must be committed before
    # upload, even if the process stops during the request.
    def self.with_owner_lock(user, &)
      OwnerLock.hold(user, "intervals-icu", &)
    end
  end
end
