module GarminConnect
  # Maps a Garmin activityType to the domain Activity sport (GAR-006). Cycling
  # is recognised by its parent type, so new bike types need no change here.
  # Other keys are added once confirmed against a real payload.
  module SportMapping
    CYCLING_TYPE_ID = 2
    TYPE_KEYS = {
      "strength_training" => "strength",
      "yoga" => "yoga",
      "indoor_rowing" => "rowing",
      "rowing" => "rowing"
    }.freeze

    def self.sport_for(activity_type)
      return "cycling" if cycling?(activity_type)

      TYPE_KEYS.fetch(activity_type["typeKey"], "other")
    end

    def self.cycling?(activity_type)
      activity_type["parentTypeId"] == CYCLING_TYPE_ID || activity_type["typeId"] == CYCLING_TYPE_ID
    end
    private_class_method :cycling?
  end
end
