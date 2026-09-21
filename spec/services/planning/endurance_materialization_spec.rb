require "rails_helper"

RSpec.describe Planning::HorizonMaterializer do
  %w[sustained alternating undulating].each do |key|
    it "persists randomly selected endurance profile #{key} and never redraws it on later requests" do
      plan = create(:training_plan, starts_on: Date.current, ends_on: Date.current + 70)
      phase = create(:plan_phase, training_plan: plan)
      workout = create(:planned_workout, training_plan: plan, plan_phase: phase, scheduled_on: Date.current)
      allow(Workouts::Variations).to receive(:for_generation).with("endurance", current_key: nil).and_return(key)

      described_class.new(plan).call
      expect(workout.reload.variation_key).to eq(key)
      expected = Workouts::Generator.new(subtype: :endurance, duration_minutes: 60, variation_key: key).call
      expect(workout.workout_steps.order(:position).pluck(:kind, :duration_seconds, :target_low_pct_ftp)).to eq(
        expected.steps.map { |step| [ step.kind, step.duration_seconds, step.target_low_pct_ftp ] })
      snapshot = workout.workout_steps.map(&:attributes)
      described_class.new(plan).call
      expect(workout.reload.workout_steps.map(&:attributes)).to eq(snapshot)
      expect(Workouts::Variations).to have_received(:for_generation).once
    end
  end
end
