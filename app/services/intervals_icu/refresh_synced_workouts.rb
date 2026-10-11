module IntervalsIcu
  # FTP changes refresh confirmed exports only; initial export/cleanup is manual.
  class RefreshSyncedWorkouts
    Result = Data.define(:refreshed_count, :error)
    FAILURE_MESSAGE = "FTP saved, but Intervals.icu workouts could not be refreshed. Check your API key in Settings and use Sync to retry.".freeze

    def initialize(profile:, client: nil)
      @profile = profile
      @client = client
    end

    def call
      Synchronization.with_owner_lock(@profile.user) do
        @profile.reload
        plan = @profile.user.training_plans.active.first
        return Result.new(refreshed_count: 0, error: nil) unless plan

        workouts = EligibleWorkouts.new(plan).call.select do |workout|
          sync = workout.intervals_icu_sync
          raise Client::RequestError, "Sync metadata owner does not match this rider" if sync && sync.user_id != @profile.user_id

          sync && sync.intervals_event_id.present? && sync.last_synced_at.present?
        end
        return Result.new(refreshed_count: 0, error: nil) if workouts.empty?
        return Result.new(refreshed_count: 0, error: FAILURE_MESSAGE) if @profile.intervals_icu_api_key.blank?

        payloads = workouts.map do |workout|
          WorkoutSerializer.new(workout: workout, ftp_watts: @profile.ftp_watts)
            .payload(external_id: workout.intervals_icu_sync.external_id)
        end
        client = @client || Client.new(api_key: @profile.intervals_icu_api_key)
        responses = client.upsert_events(payloads)
        ConfirmedUpserts.new(plan: plan, workouts: workouts, payloads: payloads).call(responses)
        Result.new(refreshed_count: workouts.size, error: nil)
      end
    rescue Client::Error, ActiveRecord::RecordInvalid
      # The FTP mutation has already committed; remote errors are a separate
      # result, never a settings-validation error or a leaked API response.
      Result.new(refreshed_count: 0, error: FAILURE_MESSAGE)
    end
  end
end
