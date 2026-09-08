module Planning
  class HorizonMaterializer
    def initialize(plan, date: Date.current)
      @plan = plan
      @date = date
    end

    def call
      @plan.planned_workouts.where(kind: %w[workout opener], detail_status: :outline, scheduled_on: @date..@date + 13).find_each do |workout|
        definition = workout.opener? ? Workouts::OpenerGenerator.new(duration_minutes: workout.duration_minutes, phase: workout.plan_phase.kind, goal: @plan.goal, discipline: @plan.discipline).call : Workouts::Generator.new(subtype: workout.subtype, duration_minutes: workout.duration_minutes, progression_level: workout.progression_level || 1, variation_key: workout.variation_key || "a", phase: workout.plan_phase.kind, goal: @plan.goal, discipline: @plan.discipline).call
        metrics = Metrics::WorkoutCalculator.new(steps: definition.steps, ftp_watts: current_ftp_watts).call
        workout.assign_attributes(
          detail_status: :structured,
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

    def current_ftp_watts
      RiderProfile.current.ftp_watts || @plan.initial_ftp_watts
    end
  end
end
