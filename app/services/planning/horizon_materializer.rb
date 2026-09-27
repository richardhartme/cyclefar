module Planning
  class HorizonMaterializer
    def initialize(plan, date: Date.current)
      @plan = plan
      @date = date
    end

    def call
      @plan.planned_workouts.planned.where(kind: %w[workout opener], detail_status: :outline, scheduled_on: @date..@date + 13).find_each do |workout|
        definition = definition_for(workout)
        metrics = Metrics::WorkoutCalculator.new(steps: definition.steps, ftp_watts: current_ftp_watts).call
        workout.assign_attributes(
          detail_status: :structured,
          variation_key: definition.variation_key,
          name: definition.name,
          purpose: definition.purpose,
          estimated_np_watts: metrics.estimated_np_watts,
          estimated_if: metrics.estimated_if,
          estimated_tss: metrics.estimated_tss,
          estimated_work_kj: metrics.estimated_work_kj)
        definition.steps.each { |step| workout.workout_steps.build(step.to_h) }
        workout.save!
      end
    end

    private

    def definition_for(workout)
      attributes = {
        duration_minutes: workout.duration_minutes,
        phase: workout.plan_phase.kind,
        goal: @plan.goal,
        discipline: @plan.discipline
      }
      return Workouts::OpenerGenerator.new(**attributes).call if workout.opener?

      Workouts::Generator.new(
        **attributes,
        subtype: workout.subtype,
        progression_level: workout.progression_level || 1,
        variation_key: Workouts::Variations.for_generation(workout.subtype, current_key: workout.variation_key)).call
    end

    def current_ftp_watts
      @plan.user.rider_profile&.ftp_watts || @plan.initial_ftp_watts
    end
  end
end
