require "digest"
require "json"

module IntervalsIcu
  # Sync the next two eligible workouts to Intervals.icu and reconcile stale syncs.
  class SyncNextTwo
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
      raise Client::RequestError, "Add an Intervals.icu API key in Settings before syncing" if @profile.intervals_icu_api_key.blank?

      client = @client || Client.new(api_key: @profile.intervals_icu_api_key)
      workouts = eligible_workouts
      payloads = workouts.map { |workout| serializer_for(workout).payload(external_id: external_id_for(workout)) }
      retain_identities!(workouts, payloads)
      responses = payloads.empty? ? [] : client.upsert_events(payloads)
      persist_upserts!(workouts, payloads, responses)
      stale_syncs = reconciled_syncs.reject { |sync| workouts.include?(sync.planned_workout) }
      begin
        client.delete_events(stale_syncs.map(&:external_id))
      rescue Client::Error
        raise PartialSyncError, "Synced #{workouts.size} workouts to Intervals.icu, but stale event cleanup failed. Sync again to retry."
      end
      IntervalsIcuSync.transaction { stale_syncs.each(&:destroy!) }
      Result.new(synced_count: workouts.size, removed_count: stale_syncs.size)
    end

    def eligible_workouts
      candidates = @plan.planned_workouts.planned.structured.where(kind: %w[workout opener]).where("scheduled_on >= ?", Date.current).order(:scheduled_on)
      candidates.reject { |workout| @plan.time_off_periods.any? { |time_off| workout.scheduled_on.between?(time_off.starts_on, time_off.ends_on) } }.first(2)
    end

    def reconciled_syncs
      @plan.user.intervals_icu_syncs.includes(:planned_workout)
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

    def persist_upserts!(workouts, payloads, responses)
      response_by_external_id = responses.to_h { |response| [ response.fetch("external_id"), response ] }
      IntervalsIcuSync.transaction do
        workouts.zip(payloads).each do |workout, payload|
          response = response_by_external_id.fetch(payload.fetch(:external_id))
          sync = workout.intervals_icu_sync
          sync.update!(intervals_event_id: response.fetch("id"), payload_digest: Digest::SHA256.hexdigest(JSON.generate(payload)), last_synced_at: Time.current)
        end
      end
    end
  end
end
