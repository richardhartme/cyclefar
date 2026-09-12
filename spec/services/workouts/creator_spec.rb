require "rails_helper"

RSpec.describe Workouts::Creator, type: :service do
  let(:plan) { create(:training_plan, starts_on: Date.current - 7, ends_on: Date.current + 70) }
  let!(:phase) { create(:plan_phase, training_plan: plan, starts_on: plan.starts_on, ends_on: plan.ends_on) }
  let(:scheduled_on) { Date.current + 2 }

  it "WKO-008 creates a canonical structured workout using the current FTP" do
    workout = described_class.new(plan).create!(
      scheduled_on: scheduled_on,
      subtype: :threshold,
      duration_minutes: 60)

    expect(workout).to have_attributes(
      training_plan: plan,
      plan_phase: phase,
      kind: "workout",
      intent: "threshold",
      subtype: "threshold",
      detail_status: "structured",
      duration_minutes: 60,
      progression_level: 1)
    expect(workout.workout_steps.sum(&:duration_seconds)).to eq(3600)
    expect(workout.estimated_tss).to be_positive
  end

  it "WKO-008 creates an opener with its canonical structure" do
    workout = described_class.new(plan).create!(
      scheduled_on: scheduled_on,
      subtype: :opener,
      duration_minutes: 45)

    expect(workout).to have_attributes(
      kind: "opener",
      intent: "intervals",
      subtype: "endurance",
      name: "Event Opener")
    expect(workout.workout_steps.map(&:label)).to include("Threshold activation", "VO2 activation")
  end

  it "WKO-008 rejects occupied and time-off dates" do
    create(:planned_workout, training_plan: plan, plan_phase: phase, scheduled_on: scheduled_on)

    expect do
      described_class.new(plan).create!(
        scheduled_on: scheduled_on,
        subtype: :endurance,
        duration_minutes: 60)
    end.to raise_error(ArgumentError, "That date already has a workout")

    empty_date = scheduled_on + 1
    create(:time_off_period, training_plan: plan, starts_on: empty_date, ends_on: empty_date)

    expect do
      described_class.new(plan).create!(
        scheduled_on: empty_date,
        subtype: :endurance,
        duration_minutes: 60)
    end.to raise_error(ArgumentError, "Workouts cannot be added during time off")
  end
end
