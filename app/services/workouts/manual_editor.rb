module Workouts
  # Edits and shuffles existing structured workouts (easier, harder, shorter, longer, adapt).
  class ManualEditor
    Snapshot = Data.define(:kind, :subtype, :duration_minutes, :estimated_if, :estimated_tss)
    Result = Data.define(:workout, :material_change, :before, :after)
    Preview = Data.define(:kind, :definition, :metrics, :before, :after)
    INTENSITY_SUBTYPES = %w[tempo sweet_spot threshold vo2_max over_under].freeze

    def initialize(workout)
      @workout = workout
      raise ArgumentError, "Only planned structured workouts can be edited" unless workout.planned? && workout.structured? && (workout.workout? || workout.opener?)
    end

    def preview(action:, subtype: nil, duration_minutes: nil, progression_level: nil, lower_targets: false)
      before = snapshot_for(@workout)
      subtype = subtype&.to_sym
      kind, definition = definition_for(action, subtype, duration_minutes, progression_level)
      if lower_targets
        raise ArgumentError, "Only easy feedback targets can be lowered" unless action.to_s == "adapt" && %w[recovery endurance].include?(@workout.subtype)

        # Keep the existing easy profile and narrow each prescribed range to its
        # lower endpoint; this also preserves any earlier re-entry reductions.
        steps = @workout.workout_steps.map do |step|
          Workouts::StepDefinition.from(step).with(
            target_high_pct_ftp: step.target_low_pct_ftp,
            end_target_high_pct_ftp: step.end_target_low_pct_ftp)
        end
        definition = definition.with(steps: steps)
      end
      metrics = Metrics::WorkoutCalculator.new(steps: definition.steps, ftp_watts: @workout.training_plan.ftp_watts_for_planning).call
      after = Snapshot.new(
        kind: kind.to_s,
        subtype: definition.subtype.to_s,
        duration_minutes: definition.duration_minutes,
        estimated_if: metrics.estimated_if,
        estimated_tss: metrics.estimated_tss)
      Preview.new(kind: kind, definition: definition, metrics: metrics, before: before, after: after)
    end

    def apply!(**attributes)
      @workout.training_plan.with_lock do
        @workout.reload
        raise ArgumentError, "Only planned structured workouts can be edited" unless @workout.planned? && @workout.structured?

        apply_under_lock!(**attributes)
      end
    end

    private

    def apply_under_lock!(prepared_preview: nil, **attributes)
      proposed = prepared_preview || preview(**attributes)
      kind, definition, metrics = proposed.kind, proposed.definition, proposed.metrics
      material_change = material_change?(proposed.before, proposed.after)
      @workout.transaction do
        if attributes[:action].to_s == "adapt"
          @workout.generation_context = @workout.generation_context.merge(
            "generated_level" => definition.progression_level,
            "generated_tss" => metrics.estimated_tss,
            "load_adjustments" => definition.load_adjustments)
        end
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
      Result.new(workout: @workout, material_change: material_change, before: proposed.before, after: proposed.after)
    end

    def definition_for(action, subtype, duration_minutes, progression_level)
      if action.to_s == "change" && subtype == :opener
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
      when "same" then [ current_level, Variations.next_key(@workout.variation_key || Variations.default_key(@workout.subtype), subtype: @workout.subtype), @workout.duration_minutes, @workout.subtype ]
      when "easier" then [ [ current_level - 1, 1 ].max, boundary_variation(current_level == 1), @workout.duration_minutes, @workout.subtype ]
      when "harder" then [ [ current_level + 1, 7 ].min, boundary_variation(current_level == 7), @workout.duration_minutes, @workout.subtype ]
      when "shorter" then [ current_level, @workout.variation_key, @workout.duration_minutes - 15, @workout.subtype ]
      when "longer" then [ current_level, @workout.variation_key, @workout.duration_minutes + 15, @workout.subtype ]
      when "change" then [ current_level, Variations.for_generation(subtype), Integer(duration_minutes), subtype.to_s ]
      when "adapt" then [ Integer(progression_level).clamp(1, 7), @workout.variation_key, @workout.duration_minutes, @workout.subtype ]
      else raise ArgumentError, "Unsupported workout action"
      end
      raise ArgumentError, "Workout duration cannot be below 30 minutes" if duration < Training::V1::Rules::MINIMUM_DURATION_MINUTES
      raise ArgumentError, "Unsupported workout subtype" unless Training::V1::Rules::SUBTYPE_NAMES.key?(chosen_subtype.to_sym)

      { subtype: chosen_subtype, duration_minutes: duration, progression_level: level, variation_key: variation || Variations.default_key(chosen_subtype),
        phase: @workout.plan_phase.kind, goal: @workout.training_plan.goal, discipline: @workout.training_plan.discipline,
        load_adjustments: action.to_s == "adapt" ? @workout.generation_context.fetch("load_adjustments", {}) : {} }
    end

    def boundary_variation(at_boundary)
      at_boundary ? Variations.next_key(@workout.variation_key || Variations.default_key(@workout.subtype), subtype: @workout.subtype) : @workout.variation_key
    end

    def material_change?(before, after)
      after.kind != before.kind ||
        intensity?(after.subtype) != intensity?(before.subtype) ||
        ((after.estimated_tss / before.estimated_tss) - 1).abs >= 0.15 ||
        (after.estimated_if - before.estimated_if).abs >= 0.08
    end

    def snapshot_for(workout)
      Snapshot.new(
        kind: workout.kind,
        subtype: workout.subtype,
        duration_minutes: workout.duration_minutes,
        estimated_if: workout.estimated_if,
        estimated_tss: workout.estimated_tss)
    end

    def intensity?(subtype)
      INTENSITY_SUBTYPES.include?(subtype.to_s)
    end
  end
end
