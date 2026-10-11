require "set"

module IntervalsIcu
  # Sync all upcoming structured workouts and reconcile the rider's tracked events.
  class SyncCalendar
    Result = Data.define(:synced_count, :removed_count)
    class PartialSyncError < Client::Error; end

    def initialize(plan:, profile: plan.user.rider_profile || plan.user.build_rider_profile, client: nil)
      @plan = plan
      @profile = profile
      @client = client
    end

    def call
      Synchronization.with_owner_lock(@plan.user) do
        @plan.reload
        raise Client::RequestError, "Only an active plan can be synced" unless @plan.active?

        sync
      end
    end

    private

    def sync
      raise ArgumentError, "Intervals.icu profile must belong to the plan owner" if @profile.user_id != @plan.user_id
      @profile.reload if @profile.persisted?
      raise Client::RequestError, "Add an Intervals.icu API key in Settings before syncing" if @profile.intervals_icu_api_key.blank?

      client = @client || Client.new(api_key: @profile.intervals_icu_api_key)
      workouts = eligible_workouts
      payloads = workouts.map { |workout| serializer_for(workout).payload(external_id: external_id_for(workout)) }
      retain_identities!(workouts, payloads)
      responses = payloads.empty? ? [] : client.upsert_events(payloads)
      ConfirmedUpserts.new(plan: @plan, workouts: workouts, payloads: payloads).call(responses)
      eligible_ids = workouts.map(&:id).to_set
      stale_syncs = reconciled_syncs.reject { |sync| eligible_ids.include?(sync.planned_workout_id) }
      begin
        client.delete_events(stale_syncs.map(&:external_id))
      rescue Client::Error
        raise PartialSyncError, "Synced #{workouts.size} workouts to Intervals.icu, but stale event cleanup failed. Sync again to retry."
      end
      IntervalsIcuSync.transaction { stale_syncs.each(&:destroy!) }
      Result.new(synced_count: workouts.size, removed_count: stale_syncs.size)
    end

    def eligible_workouts
      EligibleWorkouts.new(@plan).call
    end

    def reconciled_syncs
      @plan.user.intervals_icu_syncs
    end

    def serializer_for(workout)
      WorkoutSerializer.new(workout: workout, ftp_watts: @profile.ftp_watts || @plan.initial_ftp_watts)
    end

    def external_id_for(workout)
      sync = workout.intervals_icu_sync
      raise Client::RequestError, "Sync metadata owner does not match this rider" if sync && sync.user_id != @plan.user_id

      sync&.external_id || "cyclefar-workout-#{workout.id}"
    end

    def retain_identities!(workouts, payloads)
      # A timed-out upsert may still create events remotely. Retain ownership
      # before HTTP so later status/date changes or deletion cannot orphan them.
      IntervalsIcuSync.transaction do
        workouts.zip(payloads).each do |workout, payload|
          workout.create_intervals_icu_sync!(user: @plan.user, external_id: payload.fetch(:external_id)) unless workout.intervals_icu_sync
        end
      end
    end
  end
end
