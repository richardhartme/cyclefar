require_relative "../training/v1/rules"
require_relative "step_definition"

module Workouts
  # Builds cool-down segments with duration and subtype variations.
  class CoolDownBuilder
    def initialize(subtype:, duration_minutes:, compact: false)
      @subtype = subtype.to_sym
      @duration_minutes = duration_minutes
      @compact = compact
    end

    def call
      rules = Training::V1::Rules
      start = @subtype == :recovery ? rules::RECOVERY_COOL_DOWN_START : rules::COOL_DOWN_START
      finish = @subtype == :recovery ? rules::RECOVERY_COOL_DOWN_END : rules::COOL_DOWN_END
      seconds = !@compact && @duration_minutes >= rules::LONG_SESSION_MINUTES ? rules::LONG_COOL_DOWN_SECONDS : rules::COOL_DOWN_SECONDS
      [ StepDefinition.new(
        kind: "ramp",
        label: "Cool-down",
        duration_seconds: seconds,
        target_low_pct_ftp: start[0],
        target_high_pct_ftp: start[1],
        end_target_low_pct_ftp: finish[0],
        end_target_high_pct_ftp: finish[1],
        group_key: "cool_down") ].freeze
    end
  end
end
