require "rails_helper"

RSpec.describe Planning::MissedWorkoutResolver, type: :service do
  let(:plan) { create(:training_plan, starts_on: Date.current - 7, ends_on: Date.current + 70) }
  let(:phase) { create(:plan_phase, training_plan: plan, ends_on: plan.ends_on) }
  let!(:availability_template) { create(:availability_template, training_plan: plan) }
  let!(:availability_slot) { create(:availability_slot, availability_template: availability_template) }
  let(:workout) { create(:planned_workout, training_plan: plan, plan_phase: phase, scheduled_on: plan.starts_on + 1) }

  it "retains a missed workout without stacking compensatory work" do
    workout
    expect { described_class.new(workout).resolve!(mode: :leave_unchanged) }.not_to change(PlannedWorkout, :count)
    expect(workout.reload).to be_missed
  end

  it "moves to an empty date and protects completed workouts" do
    described_class.new(workout).resolve!(mode: :move, destination: (plan.starts_on + 3).iso8601)
    expect(workout.reload.scheduled_on).to eq(plan.starts_on + 3)
    expect(workout).to be_planned
    completed = create(:planned_workout, :completed, training_plan: plan, plan_phase: phase, scheduled_on: plan.starts_on + 4)
    expect { described_class.new(completed) }.to raise_error(ArgumentError)
  end

  it "retains a missed workout when replanning without adding training debt" do
    workout
    future_workout = create(:planned_workout, training_plan: plan, plan_phase: phase, scheduled_on: Date.current + 3)

    expect do
      described_class.new(workout).resolve!(mode: :replan)
    end.to change(PlannedWorkout, :count).by(1)

    expect(workout.reload).to be_missed
    expect { future_workout.reload }.to raise_error(ActiveRecord::RecordNotFound)
    next_available_date = Date.current.beginning_of_week + availability_slot.weekday - 1
    next_available_date += 7 if next_available_date < Date.current
    expect(plan.planned_workouts.where(scheduled_on: next_available_date).count).to eq(1)
  end
end
