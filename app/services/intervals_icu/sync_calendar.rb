require "digest"
require "json"
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
      raise Client::RequestError, "Add an Intervals.icu API key in Settings before syncing" if @profile.intervals_icu_api_key.blank?

      client = @client || Client.new(api_key: @profile.intervals_icu_api_key)
      workouts = eligible_workouts
      payloads = workouts.map { |workout| serializer_for(workout).payload(external_id: external_id_for(workout)) }
      retain_identities!(workouts, payloads)
      responses = payloads.empty? ? [] : client.upsert_events(payloads)
      persist_upserts!(workouts, payloads, responses)
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
      candidates = @plan.planned_workouts.planned.structured.where(kind: %w[workout opener])
        .where("scheduled_on >= ?", Date.current).includes(:workout_steps, :intervals_icu_sync).order(:scheduled_on)
      candidates = candidates.where.not(scheduled_on: @plan.target_event.event_on) if @plan.target_event
      time_off_periods = @plan.time_off_periods.to_a
      candidates.reject { |workout| time_off_periods.any? { |time_off| workout.scheduled_on.between?(time_off.starts_on, time_off.ends_on) } }
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

    def persist_upserts!(workouts, payloads, responses)
      response_by_external_id = confirmed_responses(payloads, responses)
      IntervalsIcuSync.transaction do
        workouts.zip(payloads).each do |workout, payload|
          response = response_by_external_id.fetch(payload.fetch(:external_id))
          sync = workout.intervals_icu_sync
          sync.update!(intervals_event_id: response.fetch("id"), payload_digest: Digest::SHA256.hexdigest(JSON.generate(payload)), last_synced_at: Time.current)
        end
      end
    end

    def confirmed_responses(payloads, responses)
      valid = responses.is_a?(Array) && responses.all? do |response|
        response.is_a?(Hash) && response["external_id"].is_a?(String) && response["id"].is_a?(Integer)
      end
      if valid
        by_external_id = responses.index_by { |response| response.fetch("external_id") }
        valid = responses.size == by_external_id.size && by_external_id.keys.to_set == payloads.map { |payload| payload.fetch(:external_id) }.to_set
      end
      # An incomplete bulk response must not mark uploads successful or start cleanup.
      raise Client::RequestError, "Intervals.icu did not confirm every workout. Sync again to retry." unless valid

      by_external_id
    end
  end
end
