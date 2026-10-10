module IntervalsIcu
  class RemovePlanEvents
    def initialize(plan)
      @plan = plan
    end

    # Called under the owner's advisory lock by PlanRemover, shared with sync.
    def call
      owned = @plan.user.intervals_icu_syncs
      syncs = owned.where(planned_workout_id: @plan.planned_workouts.select(:id))
        .or(owned.where(planned_workout_id: nil)).to_a
      return if syncs.empty?

      key = @plan.user.rider_profile&.intervals_icu_api_key
      if key.blank?
        raise Client::RequestError, "Add an Intervals.icu API key in Settings, then retry deleting or archiving the plan. The plan has been kept."
      end

      begin
        Client.new(api_key: key).delete_events(syncs.map(&:external_id))
      rescue Client::Error
        raise Client::RequestError, "Intervals.icu event cleanup failed. The plan has been kept. Check your API key in Settings and retry deleting or archiving the plan."
      end
      # Keep identities until confirmed deletion. If local removal rolls back,
      # retrying these external IDs is safe even when the events are already gone.
      syncs.each(&:destroy!)
    end
  end
end
