require_relative "../training/v1/rules"
require_relative "exact_duration_fitter"
require_relative "workout_definition"
require_relative "variations"

module Workouts
  # Generates WorkoutDefinitions with progression levels, durations, and variation rules.
  class Generator
    def initialize(subtype:, duration_minutes:, progression_level: 1, variation_key: nil,
      phase: :base, goal: :general_fitness, discipline: :road, load_adjustments: {})
      @load_adjustments = load_adjustments.transform_keys(&:to_s)
      rules = Training::V1::Rules
      @subtype = member!(subtype, rules::SUBTYPE_NAMES.keys.map(&:to_s), "subtype").to_sym
      @phase = member!(phase, rules::PHASES, "phase")
      @goal = member!(goal, rules::GOALS, "goal")
      @discipline = member!(discipline, rules::DISCIPLINES, "discipline")
      keys = Variations.keys_for(@subtype)
      @variation_key = member!(variation_key || Variations.default_key(@subtype), keys, "variation key")
      unless duration_minutes.is_a?(Integer) && duration_minutes >= rules::MINIMUM_DURATION_MINUTES
        raise ArgumentError, "duration_minutes must be a whole number of at least #{rules::MINIMUM_DURATION_MINUTES}"
      end
      unless progression_level.is_a?(Integer) && rules::PROGRESSION_LEVELS.cover?(progression_level)
        raise ArgumentError, "progression_level must be an integer from 1 to 7"
      end
      @duration_minutes = duration_minutes
      @level = progression_level
    end

    def call
      fit = ExactDurationFitter.new(
        subtype: @subtype,
        duration_minutes: @duration_minutes,
        progression_level: @level,
        variation_key: @variation_key,
        easy_filler: @load_adjustments["easy_filler"] == true).call
      steps = fit.steps
      if @load_adjustments["lower_targets"] == true
        steps = steps.map do |step|
          next step unless step.group_key == "main"

          step.with(target_high_pct_ftp: step.target_low_pct_ftp, end_target_high_pct_ftp: step.end_target_low_pct_ftp)
        end
      end
      rules = Training::V1::Rules
      reason_codes = [ "#{@subtype}_main_set" ]
      reason_codes << "duration_level_reduced" if fit.progression_level && fit.progression_level < @level
      reason_codes << "short_main_set" if fit.shortened
      reason_codes << "compressed_warm_up" if fit.compressed
      WorkoutDefinition.new(
        engine_version: rules::ENGINE_VERSION,
        subtype: @subtype.to_s,
        duration_minutes: @duration_minutes,
        requested_progression_level: @level,
        progression_level: fit.progression_level,
        variation_key: @variation_key,
        phase: @phase,
        goal: @goal,
        discipline: @discipline,
        name: "#{rules::SUBTYPE_NAMES.fetch(@subtype)} #{fit.name_suffix}",
        purpose: "#{@phase.capitalize} phase. #{rules::PURPOSES.fetch(@subtype)}",
        main_set_summary: fit.summary,
        steps: steps,
        reason_codes: reason_codes,
        load_adjustments: @load_adjustments)
    end

    private

    def member!(value, options, name)
      raise ArgumentError, "unsupported #{name}" unless options.include?(value.to_s)

      value.to_s.dup.freeze
    end
  end
end
