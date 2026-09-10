require "rails_helper"

RSpec.describe Workouts::Copier, type: :service do
  let(:plan) { create(:training_plan, starts_on: Date.current - 7, ends_on: Date.current + 70) }
  let(:phase) { create(:plan_phase, training_plan: plan, ends_on: plan.ends_on) }
  let(:workout) { create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, scheduled_on: Date.current - 1) }

  it "copies canonical steps to an empty date and recalculates metrics at the current FTP" do
    Settings::Update.new(profile: RiderProfile.current, attributes: { ftp_watts: 300 }).call
    destination = Date.current + 2
    expected_metrics = Metrics::WorkoutCalculator.new(steps: workout.workout_steps, ftp_watts: 300).call

    copy = described_class.new(workout).copy_to!(destination: destination)

    expect(copy).to be_planned
    expect(copy).to be_structured
    expect(copy).to have_attributes(
      training_plan: plan,
      plan_phase: phase,
      scheduled_on: destination,
      subtype: workout.subtype,
      duration_minutes: workout.duration_minutes,
      progression_level: workout.progression_level,
      variation_key: workout.variation_key,
      name: workout.name,
      purpose: workout.purpose)
    expect(copy.estimated_np_watts).to be_within(0.0001).of(expected_metrics.estimated_np_watts)
    expect(copy.estimated_if).to be_within(0.00001).of(expected_metrics.estimated_if)
    expect(copy.estimated_tss).to be_within(0.0001).of(expected_metrics.estimated_tss)
    expect(copy.estimated_work_kj).to be_within(0.0001).of(expected_metrics.estimated_work_kj)
    expect(copy.workout_steps.map { |step| step.attributes.slice(*Workouts::Copier::STEP_ATTRIBUTES.map(&:to_s)) }).to eq(
      workout.workout_steps.map { |step| step.attributes.slice(*Workouts::Copier::STEP_ATTRIBUTES.map(&:to_s)) }
    )
    expect(workout.reload.scheduled_on).to eq(Date.current - 1)
  end

  it "rejects an occupied destination and non-editable source" do
    create(:planned_workout, training_plan: plan, plan_phase: phase, scheduled_on: Date.current + 2)

    expect { described_class.new(workout).copy_to!(destination: Date.current + 2) }.to raise_error(ArgumentError, "That date already has a workout")
    expect { described_class.new(create(:planned_workout, :completed, training_plan: plan, plan_phase: phase, scheduled_on: Date.current + 3)) }.to raise_error(ArgumentError, "Only planned structured workouts can be copied")
  end
end
