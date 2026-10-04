require_relative "rules"

module Planning
  module V1
    # Calendar-based stages also cover short ramps that skip some quarters.
    class ReturnRamp
      def initialize(ends_on:, days:)
        @ends_on, @days = ends_on, days
      end

      def stage_on(date)
        [ ((date - @ends_on - 1) * 4 / @days).floor, 3 ].min
      end

      def duration_factor(date)
        Rules::RETURN_RAMP_DURATION_FACTORS.fetch(stage_on(date))
      end

      def target_band(date, intensity:)
        stage = stage_on(date)
        return Rules::RETURN_RAMP_TARGET_BANDS.fetch(stage) if stage < 2
        return Training::V1::Rules::TARGETS[:tempo] if stage == 2 && intensity

        nil
      end

      def progression_level(date, baseline:)
        # Hold the reduced level through the ramp; count new hard weeks only
        # after its end, rather than recovering the old level during re-entry.
        weeks = [ ((date - @ends_on - @days - 1) / 7).floor, 0 ].max
        (baseline - Rules::RETURN_RAMP_LEVEL_REDUCTION + weeks).clamp(1, 7)
      end
    end
  end
end
