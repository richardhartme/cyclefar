require "rails_helper"

RSpec.describe Planning::HorizonMaterializer do
  it "uses the passed plan's rider FTP without structuring another rider's horizon" do
    plan = create(:training_plan, starts_on: Date.current - 7, ends_on: Date.current + 70)
    other_plan = create(:training_plan, starts_on: plan.starts_on, ends_on: plan.ends_on)
    create(:rider_profile, user: other_plan.user, ftp_watts: 410)
    create(:rider_profile, user: plan.user, ftp_watts: 290)
    phase = create(:plan_phase, training_plan: plan, starts_on: plan.starts_on, ends_on: plan.ends_on)
    other_phase = create(:plan_phase, training_plan: other_plan, starts_on: other_plan.starts_on, ends_on: other_plan.ends_on)
    workout = create(:planned_workout, training_plan: plan, plan_phase: phase, scheduled_on: Date.current + 1)
    other_workout = create(:planned_workout, training_plan: other_plan, plan_phase: other_phase, scheduled_on: Date.current + 1)

    described_class.new(plan).call

    expected = Metrics::WorkoutCalculator.new(steps: workout.reload.workout_steps, ftp_watts: 290).call
    expect(workout).to be_structured
    expect(workout.estimated_np_watts).to be_within(0.001).of(expected.estimated_np_watts)
    expect(workout.estimated_work_kj).to be_within(0.001).of(expected.estimated_work_kj)
    expect(other_workout.reload).to be_outline
  end

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
