module Workouts
  # Copies structured planned workouts to new dates within a plan.
  class Copier
    STEP_ATTRIBUTES = %i[
      position
      kind
      label
      duration_seconds
      target_low_pct_ftp
      target_high_pct_ftp
      end_target_low_pct_ftp
      end_target_high_pct_ftp
      group_key
      group_iteration
    ].freeze

    def initialize(workout)
      @workout = workout
      raise ArgumentError, "Only planned structured workouts can be copied" unless workout.planned? && workout.structured? && workout.workout?
    end

    def copy_to!(destination:)
      plan.with_lock do
        @workout.reload
        raise ArgumentError, "Only planned structured workouts can be copied" unless @workout.planned? && @workout.structured? && @workout.workout?

        copy_under_lock!(destination: destination)
      end
    end

    private

    def copy_under_lock!(destination:)
      phase = DestinationValidator.new(plan).validate!(destination)

      PlannedWorkout.transaction do
        copy = plan.planned_workouts.build(copy_attributes(destination, phase))
        @workout.workout_steps.each do |step|
          copy.workout_steps.build(step.attributes.symbolize_keys.slice(*STEP_ATTRIBUTES))
        end
        copy.save!
        copy
      end
    end

    def plan
      @workout.training_plan
    end

    def copy_attributes(destination, phase)
      metrics = Metrics::WorkoutCalculator.new(steps: @workout.workout_steps, ftp_watts: plan.ftp_watts_for_planning).call
      {
        plan_phase: phase,
        scheduled_on: destination,
        kind: @workout.kind,
        intent: @workout.intent,
        subtype: @workout.subtype,
        duration_minutes: @workout.duration_minutes,
        progression_level: @workout.progression_level,
        variation_key: @workout.variation_key,
        name: @workout.name,
        purpose: @workout.purpose,
        detail_status: :structured,
        estimated_np_watts: metrics.estimated_np_watts,
        estimated_if: metrics.estimated_if,
        estimated_tss: metrics.estimated_tss,
        estimated_work_kj: metrics.estimated_work_kj
      }
    end
  end
end
