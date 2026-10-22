module Workouts
  # Copies structured planned workouts to new dates within a plan.
  class Copier
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
        copy.replace_steps(@workout.workout_steps.map { |step| StepDefinition.from(step) })
        copy.assign_metrics(Metrics::WorkoutCalculator.new(steps: @workout.workout_steps, ftp_watts: plan.ftp_watts_for_planning).call)
        copy.save!
        copy
      end
    end

    def plan
      @workout.training_plan
    end

    def copy_attributes(destination, phase)
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
        detail_status: :structured
      }
    end
  end
end
