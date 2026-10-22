module Workouts
  # Edits and shuffles existing structured workouts (easier, harder, shorter, longer, adapt).
  class ManualEditor
    def initialize(workout)
      @workout = workout
      raise ArgumentError, "Only planned structured workouts can be edited" unless workout.planned? && workout.structured? && (workout.workout? || workout.opener?)
    end

    def preview(action:, subtype: nil, duration_minutes: nil, progression_level: nil, lower_targets: false)
      if %w[easier harder].include?(action.to_s)
        raise ArgumentError, "Only easy feedback targets can be lowered" if lower_targets

        return directional_preview(action)
      end

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
      after = WorkoutSnapshot.new(
        kind: kind,
        subtype: definition.subtype.to_s,
        duration_minutes: definition.duration_minutes,
        estimated_if: metrics.estimated_if,
        estimated_tss: metrics.estimated_tss)
      EditPreview.new(kind: kind, definition: definition, metrics: metrics, before: before, after: after)
    end

    def apply!(**attributes)
      @workout.training_plan.with_lock do
        @workout.reload
        raise ArgumentError, "Only planned structured workouts can be edited" unless @workout.planned? && @workout.structured?

        apply_under_lock!(**attributes)
      end
    end

    private

    def directional_preview(action)
      raise ArgumentError, "Only a regular workout can be shuffled" unless @workout.workout?

      selected = DirectionalAdjustment.new(
        action: action,
        steps: @workout.workout_steps,
        ftp_watts: @workout.training_plan.ftp_watts_for_planning,
        progression_level: @workout.progression_level,
        maximum_level: Planning::LoadContext.new(@workout.training_plan).maximum_level(@workout),
        tss_scale: @workout.class.columns_hash.fetch("estimated_tss").scale,
        subtype: @workout.subtype,
        duration_minutes: @workout.duration_minutes,
        variation_key: @workout.variation_key,
        phase: @workout.plan_phase.kind,
        goal: @workout.training_plan.goal,
        discipline: @workout.training_plan.discipline,
        load_adjustments: @workout.generation_context.fetch("load_adjustments", {})).call
      before = snapshot_for(@workout).with(
        estimated_if: selected.current_metrics.estimated_if,
        estimated_tss: selected.current_metrics.estimated_tss)
      after = before.with(
        estimated_if: selected.metrics.estimated_if,
        estimated_tss: selected.metrics.estimated_tss)
      EditPreview.new(
        kind: "workout",
        definition: selected.definition.with(purpose: @workout.purpose),
        metrics: selected.metrics,
        before: before,
        after: after)
    end

    def apply_under_lock!(prepared_preview: nil, **attributes)
      proposed = prepared_preview || preview(**attributes)
      kind, definition, metrics = proposed.kind, proposed.definition, proposed.metrics
      material_change = material_change?(proposed.before, proposed.after)
      @workout.transaction do
        @workout.apply_definition(
          definition,
          metrics,
          track_generation: attributes[:action].to_s == "adapt",
          kind: kind,
          intent: kind == "opener" ? :intervals : @workout.intent)
        @workout.save!
      end
      EditResult.new(workout: @workout, material_change: material_change, before: proposed.before, after: proposed.after)
    end

    def definition_for(action, subtype, duration_minutes, progression_level)
      factory = DefinitionFactory.for(@workout.training_plan)
      phase = @workout.plan_phase.kind
      if action.to_s == "change" && subtype == :opener
        return [ "opener", factory.build(kind: "opener", duration_minutes: Integer(duration_minutes), phase: phase) ]
      end

      raise ArgumentError, "Only a regular workout can be shuffled" unless @workout.workout? || action.to_s == "change"

      [ "workout", factory.build(kind: "workout", phase: phase, **next_attributes(action, subtype, duration_minutes, progression_level)) ]
    end

    def next_attributes(action, subtype, duration_minutes, progression_level)
      edit = EditActions.for(action).new(@workout, subtype: subtype, duration_minutes: duration_minutes, progression_level: progression_level)
      raise ArgumentError, "Workout duration cannot be below 30 minutes" if edit.duration < Training::Rules::MINIMUM_DURATION_MINUTES
      raise ArgumentError, "Unsupported workout subtype" unless Training::Rules::SUBTYPE_NAMES.key?(edit.subtype.to_sym)

      { subtype: edit.subtype, duration_minutes: edit.duration, progression_level: edit.level,
        variation_key: edit.variation_key || Variations.default_key(edit.subtype), load_adjustments: edit.load_adjustments }
    end

    def material_change?(before, after)
      after.kind != before.kind ||
        intensity?(after.subtype) != intensity?(before.subtype) ||
        ((after.estimated_tss / before.estimated_tss) - 1).abs >= Training::Rules::MATERIAL_CHANGE_TSS_RATIO ||
        (after.estimated_if - before.estimated_if).abs >= Training::Rules::MATERIAL_CHANGE_IF_DELTA
    end

    def snapshot_for(workout)
      WorkoutSnapshot.new(
        kind: workout.kind,
        subtype: workout.subtype,
        duration_minutes: workout.duration_minutes,
        estimated_if: workout.estimated_if,
        estimated_tss: workout.estimated_tss)
    end

    def intensity?(subtype)
      Training::Rules::INTENSITY_SUBTYPES.include?(subtype.to_s)
    end
  end
end
