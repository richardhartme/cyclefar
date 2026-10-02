module GeneratedWorkouts
  def generated_workout(plan:, phase:, date:, level: 4, duration: 60, subtype: :threshold, variation: nil)
    definition = Workouts::Generator.new(
      subtype: subtype,
      duration_minutes: duration,
      progression_level: level,
      variation_key: variation,
      phase: phase.kind,
      goal: plan.goal,
      discipline: plan.discipline).call
    metrics = Metrics::WorkoutCalculator.new(steps: definition.steps, ftp_watts: plan.ftp_watts_for_planning).call
    workout = plan.planned_workouts.build(
      plan_phase: phase,
      scheduled_on: date,
      intent: subtype,
      subtype: subtype,
      duration_minutes: duration,
      detail_status: :structured,
      name: definition.name,
      purpose: definition.purpose,
      progression_level: definition.progression_level,
      variation_key: definition.variation_key)
    PlannedWorkout::METRICS.each { |key| workout.public_send("#{key}=", metrics.public_send(key)) }
    definition.steps.each { |step| workout.workout_steps.build(step.to_h) }
    workout.save!
    workout
  end
end

RSpec.configure do |config|
  config.include GeneratedWorkouts, generated_workouts: true
end
