require_relative "../training/rules"
require_relative "step_definition"

module Workouts
  # Builds warm-up segments with optional primer efforts and settlement.
  class WarmUpBuilder
    def initialize(subtype:, compact: false)
      @subtype = subtype.to_sym
      @compact = compact
    end

    def call
      rules = Training::Rules
      config = rules::WARM_UPS.fetch(@subtype)
      compressed = @compact && config[:primers].positive?
      duration = compressed ? rules::COMPACT_WARM_UP_SECONDS : config[:ramp]
      steps = [ StepDefinition.new(
        kind: "ramp",
        label: "Warm-up",
        duration_seconds: duration,
        target_low_pct_ftp: config[:start][0],
        target_high_pct_ftp: config[:start][1],
        end_target_low_pct_ftp: config[:finish][0],
        end_target_high_pct_ftp: config[:finish][1],
        group_key: "warm_up") ]
      return steps.freeze if compressed

      config[:primers].times do
        steps << steady("Preparation effort", rules::PRIMER_SECONDS, config[:primer_target])
        steps << steady("Easy between efforts", rules::PRIMER_RECOVERY_SECONDS, rules::TARGETS[:easy])
      end
      steps << steady("Settle before main set", config[:settle], rules::TARGETS[:easy]) if config[:settle].positive?
      steps.freeze
    end

    private

    def steady(label, seconds, target)
      StepDefinition.new(
        kind: "steady",
        label: label,
        duration_seconds: seconds,
        target_low_pct_ftp: target[0],
        target_high_pct_ftp: target[1],
        group_key: "warm_up")
    end
  end
end
