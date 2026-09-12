module Workouts
  class ManualEditor
    Result = Data.define(:workout, :material_change)
    INTENSITY_SUBTYPES = %w[tempo sweet_spot threshold vo2_max over_under].freeze

    def initialize(workout)
      @workout = workout
      raise ArgumentError, "Only planned structured workouts can be edited" unless workout.planned? && workout.structured? && (workout.workout? || workout.opener?)
    end

    def apply!(action:, subtype: nil, duration_minutes: nil, progression_level: nil)
      kind, definition = definition_for(action, subtype, duration_minutes, progression_level)
      metrics = Metrics::WorkoutCalculator.new(steps: definition.steps, ftp_watts: current_ftp_watts).call
      material_change = material_change?(kind, definition.subtype, metrics)
      @workout.transaction do
        @workout.workout_steps.destroy_all
        @workout.assign_attributes(
          kind: kind,
          intent: kind == :opener ? :intervals : @workout.intent,
          subtype: definition.subtype,
          duration_minutes: definition.duration_minutes,
          progression_level: definition.progression_level,
          variation_key: definition.variation_key,
          name: definition.name,
          purpose: definition.purpose,
          estimated_np_watts: metrics.estimated_np_watts,
          estimated_if: metrics.estimated_if,
          estimated_tss: metrics.estimated_tss,
          estimated_work_kj: metrics.estimated_work_kj)
        definition.steps.each { |step| @workout.workout_steps.build(step.to_h) }
        @workout.save!
      end
      Result.new(workout: @workout, material_change: material_change)
    end

    private

    def definition_for(action, subtype, duration_minutes, progression_level)
      if action.to_s == "change" && subtype.to_s == "opener"
        return [ :opener, opener_definition(duration_minutes) ]
      end

      raise ArgumentError, "Only a regular workout can be shuffled" unless @workout.workout? || action.to_s == "change"

      attributes = next_attributes(action, subtype, duration_minutes, progression_level)
      [ :workout, Generator.new(**attributes).call ]
    end

    def opener_definition(duration_minutes)
      OpenerGenerator.new(
        duration_minutes: Integer(duration_minutes),
        phase: @workout.plan_phase.kind,
        goal: @workout.training_plan.goal,
        discipline: @workout.training_plan.discipline).call
    end

    def next_attributes(action, subtype, duration_minutes, progression_level)
      current_level = @workout.progression_level || 1
      level, variation, duration, chosen_subtype = case action.to_s
      when "same" then [ current_level, Variations.next_key(@workout.variation_key || "a"), @workout.duration_minutes, @workout.subtype ]
      when "easier" then [ [ current_level - 1, 1 ].max, boundary_variation(current_level == 1), @workout.duration_minutes, @workout.subtype ]
      when "harder" then [ [ current_level + 1, 7 ].min, boundary_variation(current_level == 7), @workout.duration_minutes, @workout.subtype ]
      when "shorter" then [ current_level, @workout.variation_key, @workout.duration_minutes - 15, @workout.subtype ]
      when "longer" then [ current_level, @workout.variation_key, @workout.duration_minutes + 15, @workout.subtype ]
      when "change" then [ current_level, @workout.variation_key, Integer(duration_minutes), subtype.to_s ]
      when "adapt" then [ Integer(progression_level), @workout.variation_key, @workout.duration_minutes, @workout.subtype ]
      else raise ArgumentError, "Unsupported workout action"
      end
      raise ArgumentError, "Workout duration cannot be below 30 minutes" if duration < Training::V1::Rules::MINIMUM_DURATION_MINUTES
      raise ArgumentError, "Unsupported workout subtype" unless Training::V1::Rules::SUBTYPE_NAMES.key?(chosen_subtype.to_sym)

      { subtype: chosen_subtype, duration_minutes: duration, progression_level: level, variation_key: variation || "a",
        phase: @workout.plan_phase.kind, goal: @workout.training_plan.goal, discipline: @workout.training_plan.discipline }
    end

    def boundary_variation(at_boundary)
      at_boundary ? Variations.next_key(@workout.variation_key || "a") : @workout.variation_key
    end

    def material_change?(kind, subtype, metrics)
      kind.to_s != @workout.kind ||
        intensity?(subtype) != intensity?(@workout.subtype) ||
        ((metrics.estimated_tss / @workout.estimated_tss) - 1).abs >= 0.15 ||
        (metrics.estimated_if - @workout.estimated_if).abs >= 0.08
    end

    def current_ftp_watts
      RiderProfile.current.ftp_watts || @workout.training_plan.initial_ftp_watts
    end

    def intensity?(subtype)
      INTENSITY_SUBTYPES.include?(subtype.to_s)
    end
  end
end
