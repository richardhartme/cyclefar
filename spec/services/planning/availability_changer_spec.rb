require "rails_helper"

RSpec.describe Planning::AvailabilityChanger, type: :service do
  let(:plan) { create(:training_plan, :event, starts_on: Date.current - 7, ends_on: Date.current + 70, progression_mode: :continuous, hard_weeks_before_recovery: nil) }
  let(:phase) { create(:plan_phase, training_plan: plan, starts_on: plan.starts_on, ends_on: plan.ends_on) }
  let(:initial_template) { create(:availability_template, training_plan: plan, effective_from: plan.starts_on) }
  let(:next_week) { Date.current.beginning_of_week + 7 }
  let(:slots) do
    [
      { weekday: 2, duration_minutes: 90, intent: "threshold" },
      { weekday: 4, duration_minutes: 60, intent: "endurance" }
    ]
  end

  before do
    travel_to Date.new(2026, 9, 7)
    create(:availability_slot, availability_template: initial_template, weekday: 2, duration_minutes: 60, intent: :intervals)
  end

  it "creates a one-week template and replaces only future prescriptions in that week" do
    other_plan = create(:training_plan, starts_on: plan.starts_on, ends_on: plan.ends_on)
    other_phase = create(:plan_phase, training_plan: other_plan, starts_on: other_plan.starts_on, ends_on: other_plan.ends_on)
    other_workout = create(:planned_workout, :structured, training_plan: other_plan, plan_phase: other_phase, scheduled_on: next_week + 1)
    other_attributes = other_workout.attributes.deep_dup
    create(:rider_profile, user: other_plan.user, ftp_watts: 410)
    create(:rider_profile, user: plan.user, ftp_watts: 290)
    old_workout = create(:planned_workout, training_plan: plan, plan_phase: phase, scheduled_on: next_week + 1)
    past_workout = create(:planned_workout, training_plan: plan, plan_phase: phase, scheduled_on: Date.current - 1)

    template = described_class.new(plan: plan, slots: slots, effective_from: next_week + 2, scope: :one_week).apply!

    expect(template).to be_one_week_override
    expect(template.effective_from).to eq(next_week)
    expect(template.effective_until).to eq(next_week + 6)
    expect(template.availability_slots.pluck(:weekday, :duration_minutes, :intent)).to include([ 2, 90, "threshold" ])
    expect { old_workout.reload }.to raise_error(ActiveRecord::RecordNotFound)
    expect(past_workout.reload).to be_planned
    replacement = plan.planned_workouts.find_by!(scheduled_on: next_week + 1)
    expect(replacement).to be_structured
    expect(replacement).to have_attributes(intent: "threshold", duration_minutes: 90, plan_phase: phase)
    expected = Metrics::WorkoutCalculator.new(steps: replacement.workout_steps, ftp_watts: 290).call
    expect(replacement.estimated_np_watts).to be_within(0.001).of(expected.estimated_np_watts)
    expect(replacement.estimated_work_kj).to be_within(0.001).of(expected.estimated_work_kj)
    expect(plan.planned_workouts.where(scheduled_on: next_week + 1).count).to eq(1)
    expect(other_workout.reload.attributes).to eq(other_attributes)
  end

  it "versions an ongoing change while preserving past workouts and event items" do
    event = create(:target_event, training_plan: plan, event_on: plan.ends_on)
    past_workout = create(:planned_workout, training_plan: plan, plan_phase: phase, scheduled_on: Date.current - 1)
    ftp_test = create(:planned_workout, :ftp_test, training_plan: plan, plan_phase: phase, scheduled_on: next_week + 2)
    completed = create(:planned_workout, :completed, training_plan: plan, plan_phase: phase, scheduled_on: next_week + 4)

    template = described_class.new(plan: plan, slots: slots, effective_from: next_week, scope: :from_date).apply!

    expect(initial_template.reload.effective_until).to eq(next_week - 1)
    expect(template).to be_from_date_change
    expect(template.effective_until).to be_nil
    expect(past_workout.reload).to be_planned
    expect(completed.reload).to be_completed
    expect(ftp_test.reload).to be_ftp_test
    expect(plan.target_event).to eq(event)
    expect(plan.plan_phases).to contain_exactly(phase)
  end

  it "rejects an empty training week" do
    expect do
      described_class.new(plan: plan, slots: [], effective_from: next_week, scope: :one_week).apply!
    end.to raise_error(ArgumentError, "Choose at least one available training day")
  end
end
