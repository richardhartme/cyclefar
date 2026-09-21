require_relative "../training/v1/rules"
require_relative "exact_duration_fitter"
require_relative "workout_definition"
require_relative "variations"

module Workouts
  class Generator
    def initialize(subtype:, duration_minutes:, progression_level: 1, variation_key: "a",
      phase: :base, goal: :general_fitness, discipline: :road)
      rules = Training::V1::Rules
      @subtype = member!(subtype, rules::SUBTYPE_NAMES.keys.map(&:to_s), "subtype")
      @phase = member!(phase, rules::PHASES, "phase")
      @goal = member!(goal, rules::GOALS, "goal")
      @discipline = member!(discipline, rules::DISCIPLINES, "discipline")
      keys = @subtype == "endurance" ? rules::ENDURANCE_VARIATION_KEYS : rules::VARIATION_KEYS
      @variation_key = member!(variation_key, keys, "variation key")
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
        variation_key: @variation_key).call
      rules = Training::V1::Rules
      reason_codes = [ "#{@subtype}_main_set" ]
      reason_codes << "duration_level_reduced" if fit.progression_level && fit.progression_level < @level
      reason_codes << "short_main_set" if fit.shortened
      reason_codes << "compressed_warm_up" if fit.compressed
      WorkoutDefinition.new(
        engine_version: rules::ENGINE_VERSION,
        subtype: @subtype,
        duration_minutes: @duration_minutes,
        requested_progression_level: @level,
        progression_level: fit.progression_level,
        variation_key: @variation_key,
        phase: @phase,
        goal: @goal,
        discipline: @discipline,
        name: "#{rules::SUBTYPE_NAMES.fetch(@subtype.to_sym)} #{fit.name_suffix}",
        purpose: "#{@phase.capitalize} phase. #{rules::PURPOSES.fetch(@subtype.to_sym)}",
        main_set_summary: fit.summary,
        steps: fit.steps,
        reason_codes: reason_codes)
    end

    private

    def member!(value, options, name)
      raise ArgumentError, "unsupported #{name}" unless options.include?(value.to_s)

      value.to_s.dup.freeze
    end
  end
end
