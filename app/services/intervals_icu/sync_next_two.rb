require "digest"
require "json"

module IntervalsIcu
  class SyncNextTwo
    Result = Data.define(:synced_count, :removed_count)

    def initialize(plan:, profile: plan.user.rider_profile || plan.user.build_rider_profile, client: nil)
      @plan = plan
      @profile = profile
      @client = client
    end

    def call
      raise Client::RequestError, "Add an Intervals.icu API key in Settings before syncing" if @profile.intervals_icu_api_key.blank?

      client = @client || Client.new(api_key: @profile.intervals_icu_api_key)
      workouts = eligible_workouts
      payloads = workouts.map { |workout| serializer_for(workout).payload(external_id: external_id_for(workout)) }
      responses = payloads.empty? ? [] : client.upsert_events(payloads)
      stale_syncs = reconciled_syncs.reject { |sync| workouts.include?(sync.planned_workout) }
      client.delete_events(stale_syncs.map(&:external_id))
      persist_success!(workouts, payloads, responses, stale_syncs)
      Result.new(synced_count: workouts.size, removed_count: stale_syncs.size)
    end

    private

    def eligible_workouts
      candidates = @plan.planned_workouts.planned.structured.where(kind: %w[workout opener]).where("scheduled_on >= ?", Date.current).order(:scheduled_on)
      candidates.reject { |workout| @plan.time_off_periods.any? { |time_off| workout.scheduled_on.between?(time_off.starts_on, time_off.ends_on) } }.first(2)
    end

    def reconciled_syncs
      IntervalsIcuSync.includes(:planned_workout).select do |sync|
        workout = sync.planned_workout
        workout.nil? || (workout.training_plan_id == @plan.id && workout.planned? && workout.scheduled_on >= Date.current)
      end
    end

    def serializer_for(workout)
      WorkoutSerializer.new(workout: workout, ftp_watts: @profile.ftp_watts || @plan.initial_ftp_watts)
    end

    def external_id_for(workout)
      workout.intervals_icu_sync&.external_id || "cyclefar-workout-#{workout.id}"
    end

    def persist_success!(workouts, payloads, responses, stale_syncs)
      response_by_external_id = responses.to_h { |response| [ response.fetch("external_id"), response ] }
      IntervalsIcuSync.transaction do
        workouts.zip(payloads).each do |workout, payload|
          response = response_by_external_id.fetch(payload.fetch(:external_id))
          sync = workout.intervals_icu_sync || workout.build_intervals_icu_sync(external_id: payload.fetch(:external_id))
          sync.update!(intervals_event_id: response.fetch("id"), payload_digest: Digest::SHA256.hexdigest(JSON.generate(payload)), last_synced_at: Time.current)
        end
        stale_syncs.each(&:destroy!)
      end
    end
  end
end
