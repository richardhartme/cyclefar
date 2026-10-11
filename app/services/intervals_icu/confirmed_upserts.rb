require "digest"
require "json"
require "set"

module IntervalsIcu
  # Only a complete confirmation advances successful-sync metadata.
  class ConfirmedUpserts
    def initialize(plan:, workouts:, payloads:)
      @plan = plan
      @workouts = workouts
      @payloads = payloads
    end

    def call(responses)
      response_by_external_id = confirmed_responses(responses)
      @plan.with_lock do
        raise Client::RequestError, "Only an active plan can be synced" unless @plan.active?
        eligible_ids = EligibleWorkouts.new(@plan).call.map(&:id).to_set

        @workouts.zip(@payloads).each do |workout, payload|
          # Re-read ownership/linkage after HTTP: removal can detach a retained
          # identity while an upload is in flight. Never reattach that record.
          sync = @plan.user.intervals_icu_syncs.find_by(external_id: payload.fetch(:external_id), planned_workout_id: workout.id)
          unless sync && eligible_ids.include?(workout.id)
            raise Client::RequestError, "Workouts changed during sync. Sync again to retry."
          end

          response = response_by_external_id.fetch(payload.fetch(:external_id))
          sync.update!(intervals_event_id: response.fetch("id"), payload_digest: Digest::SHA256.hexdigest(JSON.generate(payload)), last_synced_at: Time.current)
        end
      end
    end

    private

    def confirmed_responses(responses)
      valid = responses.is_a?(Array) && responses.all? do |response|
        response.is_a?(Hash) && response["external_id"].is_a?(String) && response["id"].is_a?(Integer) && response["id"].positive?
      end
      if valid
        by_external_id = responses.index_by { |response| response.fetch("external_id") }
        valid = responses.size == by_external_id.size && by_external_id.keys.to_set == @payloads.map { |payload| payload.fetch(:external_id) }.to_set
      end
      raise Client::RequestError, "Intervals.icu did not confirm every workout. Sync again to retry." unless valid

      by_external_id
    end
  end
end
