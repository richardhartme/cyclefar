require_relative "step_definition"
require_relative "../training/rules"

module Workouts
  # Main work stays in its return band; easier preparation and recovery may
  # stay below it, but no primer or ramp endpoint exceeds its upper limit.
  class TargetBandLimiter
    def initialize(steps:, band:)
      unless band.is_a?(Array) && band.size == 2 &&
          band.all? { |value| value.is_a?(Numeric) && value.real? && value.finite? && value.positive? } &&
          band.first <= band.last && band.last <= Training::Rules::MAXIMUM_TARGET_PCT
        raise ArgumentError, "Target band must be a positive ordered FTP range within V1 limits"
      end
      @steps, @band = steps, band
    end

    def call
      @steps.map do |step|
        attributes = %i[target_low_pct_ftp target_high_pct_ftp end_target_low_pct_ftp end_target_high_pct_ftp].to_h do |field|
          value = step.public_send(field)
          limited = value && (step.group_key == "main" ? value.clamp(*@band) : [ value, @band.last ].min)
          [ field, limited ]
        end
        step.with(**attributes)
      end.freeze
    end
  end
end
