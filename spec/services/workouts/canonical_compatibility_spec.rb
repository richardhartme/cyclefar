require "rails_helper"

RSpec.describe "Generated canonical definitions", type: :model do
  %i[recovery endurance tempo sweet_spot threshold vo2_max over_under].each do |subtype|
    it "GEN-001 / LOAD-001 round-trips #{subtype} through WorkoutStep without changing structure or metrics" do
      definition = Workouts::Generator.new(subtype: subtype, duration_minutes: 60, progression_level: 5, variation_key: Workouts::Variations.keys_for(subtype).last).call
      workout = build(
        :planned_workout,
        subtype: subtype,
        detail_status: :structured,
        name: definition.name,
        duration_minutes: definition.duration_minutes,
        progression_level: definition.progression_level,
        variation_key: definition.variation_key)
      definition.steps.each { |step| workout.workout_steps.build(step.to_h) }
      workout.save!
      persisted_steps = workout.reload.workout_steps.to_a
      expect(persisted_steps.map { |step| Workouts::StepDefinition.from(step) }).to eq(definition.steps)
      expect(Metrics::WorkoutCalculator.new(steps: persisted_steps, ftp_watts: 260).call).to eq(
        Metrics::WorkoutCalculator.new(steps: definition.steps, ftp_watts: 260).call
      )
      expect(Workouts::ProfileBuilder.new(steps: persisted_steps).call).to eq(
        Workouts::ProfileBuilder.new(steps: definition.steps).call
      )
    end
  end
end
