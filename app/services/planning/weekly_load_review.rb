module Planning
  # Read-only load review, including explicit moves outside the detail horizon.
  class WeeklyLoadReview
    Week = Data.define(:starts_on, :workouts, :estimated_tss, :limit) do
      def warning
        V1::WeeklyLoadCap.warning(starts_on) if limit && estimated_tss > limit
      end
    end

    def initialize(plan)
      @plan = plan
      @context = V1::LoadContext.new(plan)
    end

    def call
      reference = nil
      @plan.planned_workouts.includes(:plan_phase, :workout_steps).order(:scheduled_on)
        .group_by { |workout| workout.scheduled_on.beginning_of_week }.map do |starts_on, workouts|
        comparable = @context.comparable_week?(starts_on, workouts)
        loads = workouts.to_h { |workout| [ workout.id, estimated_tss(workout) ] }
        week = Week.new(
          starts_on: starts_on,
          workouts: workouts,
          estimated_tss: loads.values.sum,
          limit: comparable && reference ? V1::WeeklyLoadCap.limit(reference) : nil)
        if comparable
          reference = workouts.sum { |workout| workout.generation_context.fetch("generated_tss", loads.fetch(workout.id)).to_f }
        end
        week
      end
    end

    def warnings(from: Date.current.beginning_of_week)
      call.select { |week| week.starts_on >= from }.filter_map(&:warning)
    end

    def estimated_tss(workout)
      return workout.estimated_tss.to_f if workout.estimated_tss
      return 0 if workout.ftp_test?

      steps = if workout.structured?
        workout.workout_steps
      else
        attributes = { duration_minutes: workout.duration_minutes, phase: workout.plan_phase&.kind || "base", goal: @plan.goal, discipline: @plan.discipline }
        if workout.opener?
          Workouts::OpenerGenerator.new(**attributes).call.steps
        else
          Workouts::Generator.new(
            **attributes,
            subtype: workout.subtype,
            progression_level: workout.progression_level || 1,
            variation_key: workout.variation_key || Workouts::Variations.default_key(workout.subtype),
            load_adjustments: workout.generation_context.fetch("load_adjustments", {})).call.steps
        end
      end
      ftp = workout.completed? ? workout.completed_ftp_watts : @plan.ftp_watts_for_planning
      Metrics::WorkoutCalculator.new(steps: steps, ftp_watts: ftp).call.estimated_tss
    end
  end
end
