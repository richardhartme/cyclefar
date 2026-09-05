module Planning
  Availability = Data.define(:weekday, :duration_minutes, :intent) do
    INTENTS = %w[intervals endurance recovery vo2_max threshold sweet_spot tempo].freeze

    def initialize(weekday:, duration_minutes:, intent:)
      raise ArgumentError, "weekday must be an ISO weekday" unless weekday.is_a?(Integer) && weekday.between?(1, 7)
      raise ArgumentError, "duration must be at least 30 minutes" unless duration_minutes.is_a?(Integer) && duration_minutes >= 30
      unless INTENTS.include?(intent.to_s)
        raise ArgumentError, "unsupported workout intent"
      end

      super(weekday: weekday, duration_minutes: duration_minutes, intent: intent.to_s.dup.freeze)
    end

    def intensity?
      intent == "intervals" || %w[vo2_max threshold sweet_spot tempo].include?(intent)
    end
  end
end
