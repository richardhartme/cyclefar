require_relative "../training/v1/rules"
require_relative "step_definition"

module Workouts
  # Builds interval ladder main sets with work/recovery repetitions and variations.
  class MainSetBuilder
    Definition = Data.define(:steps, :name_suffix, :summary, :progression_level, :shortened)

    def initialize(subtype:, progression_level:, variation_key:, shortened: false)
      @subtype = subtype.to_sym
      @level = progression_level
      @variation_key = variation_key
      @shortened = shortened
    end

    def call
      rules = Training::V1::Rules
      repetitions, minutes, recovery = @shortened ? rules::SHORT_MAIN_SETS.fetch(@subtype) : rules::LADDERS.fetch(@subtype).fetch(@level - 1)
      steps = []
      repetitions.times do |index|
        steps.concat(work_steps(minutes, index + 1))
        if index < repetitions - 1
          seconds = recovery * 60
          seconds -= rules::VARIATION_RECOVERY_SHIFT_SECONDS if @variation_key == "redistributed_recovery" && index.zero?
          steps << recovery_step(seconds)
        end
      end
      # The redistributed recovery variation moves 30 seconds from the first recovery to after the final
      # effort. Work duration, work targets and total easy time remain identical.
      # It changes recovery distribution without a duration-boundary level jump.
      if @variation_key == "redistributed_recovery"
        steps << recovery_step(rules::VARIATION_RECOVERY_SHIFT_SECONDS).with(label: "Easy after main set")
      end
      summary = "#{repetitions} x #{minutes} min, #{recovery} min recovery between blocks"
      if @subtype == :over_under
        under, over = cycle
        summary += " (#{under} min under / #{over} min over)"
      end
      if @variation_key == "redistributed_recovery"
        shift = rules::VARIATION_RECOVERY_SHIFT_SECONDS
        summary += "; first recovery #{shift} sec shorter, #{shift} sec easy after main set"
      end
      Definition.new(
        steps: steps.freeze,
        name_suffix: "#{repetitions}x#{minutes}".freeze,
        summary: summary.freeze,
        progression_level: @level,
        shortened: @shortened)
    end

    private

    def work_steps(minutes, iteration)
      rules = Training::V1::Rules
      if @subtype == :over_under
        under, over = cycle
        Array.new(minutes / (under + over)) do
          [ steady("Under", under * 60, rules::TARGETS[:under], "main", iteration),
            steady("Over", over * 60, rules::TARGETS[:over], "main", iteration) ]
        end.flatten
      else
        target = case @subtype
        when :vo2_max then rules::VO2_TARGETS.fetch(minutes * 60)
        when :threshold
          @level >= rules::UPPER_THRESHOLD_LEVEL ? rules::UPPER_THRESHOLD_TARGET : rules::TARGETS[:threshold]
        else rules::TARGETS.fetch(@subtype)
        end
        [ steady(rules::SUBTYPE_NAMES.fetch(@subtype), minutes * 60, target, "main", iteration) ]
      end
    end

    def cycle
      Training::V1::Rules::OVER_UNDER_CYCLES.fetch(@shortened ? 0 : @level - 1)
    end

    def recovery_step(seconds)
      steady("Recovery between efforts", seconds, Training::V1::Rules::TARGETS[:easy], "recovery", nil)
    end

    def steady(label, seconds, target, group, iteration)
      StepDefinition.new(
        kind: "steady",
        label: label,
        duration_seconds: seconds,
        target_low_pct_ftp: target[0],
        target_high_pct_ftp: target[1],
        group_key: group,
        group_iteration: iteration)
    end
  end
end
