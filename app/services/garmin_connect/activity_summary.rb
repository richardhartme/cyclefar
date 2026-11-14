module GarminConnect
  # One activity from the Personal API's activity list, in CycleFar's terms.
  # Garmin's shapes stop here: see docs/GARMIN_CONNECT.md.
  class ActivitySummary < Data.define(
    :garmin_activity_id,
    :name,
    :external_type,
    :sport,
    :started_at,
    :local_started_at,
    :started_on,
    :duration_seconds,
    :elapsed_seconds,
    :moving_seconds,
    :distance_metres,
    :average_heart_rate_bpm,
    :max_heart_rate_bpm,
    :average_power_watts,
    :np_watts,
    :max_power_watts,
    :payload
  )
    class InvalidPayload < StandardError; end

    # Garmin sends "YYYY-MM-DD HH:MM:SS" with no offset.
    WALL_CLOCK = /\A(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})(?:\.\d+)?\z/
    # Real UTC offsets run from -12:00 to +14:00.
    UTC_OFFSETS = (-12.hours.to_i..14.hours.to_i)

    def self.from_payload(payload)
      raise InvalidPayload, "activity summary must be an object" unless payload.is_a?(Hash)

      activity_type = payload["activityType"]
      raise InvalidPayload, "activityId must be an integer" unless payload["activityId"].is_a?(Integer)
      raise InvalidPayload, "activityType is missing" unless activity_type.is_a?(Hash)

      started_at = wall_clock(payload["startTimeGMT"])
      utc_offset = (wall_clock(payload["startTimeLocal"]) - started_at).to_i
      raise InvalidPayload, "startTimeLocal is too far from startTimeGMT" unless UTC_OFFSETS.cover?(utc_offset)

      local_started_at = started_at.getlocal(utc_offset)
      new(
        garmin_activity_id: payload["activityId"],
        name: payload["activityName"],
        external_type: activity_type["typeKey"],
        sport: SportMapping.sport_for(activity_type),
        started_at: started_at,
        local_started_at: local_started_at,
        started_on: local_started_at.to_date,
        duration_seconds: payload["duration"]&.round,
        elapsed_seconds: payload["elapsedDuration"]&.round,
        moving_seconds: payload["movingDuration"]&.round,
        distance_metres: payload["distance"],
        average_heart_rate_bpm: payload["averageHR"],
        max_heart_rate_bpm: payload["maxHR"],
        average_power_watts: payload["avgPower"],
        np_watts: payload["normPower"],
        max_power_watts: payload["maxPower"],
        payload: payload)
    end

    def self.wall_clock(value)
      parts = WALL_CLOCK.match(value.to_s)&.captures
      raise InvalidPayload, "start time is not YYYY-MM-DD HH:MM:SS" unless parts

      Time.utc(*parts.map(&:to_i))
    rescue ArgumentError
      raise InvalidPayload, "start time is not a valid date"
    end
    private_class_method :wall_clock
  end
end
