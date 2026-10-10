require "rails_helper"

RSpec.describe Workouts::Remover do
  let(:plan) { create(:training_plan, starts_on: Date.current - 14, ends_on: Date.current + 70) }
  let(:phase) { create(:plan_phase, training_plan: plan, ends_on: plan.ends_on) }
  let(:workout) { create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, scheduled_on: Date.current) }

  it "removes only the selected workout, updates calendar totals and retains owned sync identity" do
    other = create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, scheduled_on: Date.current + 1)
    history = create(:planned_workout, :completed, training_plan: plan, plan_phase: phase, scheduled_on: Date.current - 1)
    sync = create(:intervals_icu_sync, planned_workout: workout, intervals_event_id: 123, last_synced_at: Time.current, payload_digest: "confirmed")
    sync_attributes = sync.attributes.except("planned_workout_id", "updated_at")
    other_attributes = other.attributes
    completed_history = [ history.attributes, history.workout_steps.map(&:attributes), history.workout_feedback.attributes ]
    totals = Planning::CalendarPresenter.new(plan).weeks.find { |week| week.starts_on == Date.current.beginning_of_week }

    described_class.new(workout).call

    expect(sync.reload.planned_workout_id).to be_nil
    expect(sync.attributes.except("planned_workout_id", "updated_at")).to eq(sync_attributes)
    expect(other.reload.attributes).to eq(other_attributes)
    expect([ history.reload.attributes, history.workout_steps.reload.map(&:attributes), history.workout_feedback.reload.attributes ]).to eq(completed_history)
    updated = Planning::CalendarPresenter.new(plan).weeks.find { |week| week.starts_on == Date.current.beginning_of_week }
    expect(updated.duration_minutes).to eq(totals.duration_minutes - workout.duration_minutes)
    expect(updated.estimated_tss).to be_within(0.0001).of(totals.estimated_tss - workout.estimated_tss)
    expect(updated.estimated_work_kj).to be_within(0.0001).of(totals.estimated_work_kj - workout.estimated_work_kj)
  end

  it "rechecks completion under the plan lock when passed a stale instance" do
    stale = PlannedWorkout.find(workout.id)
    Adaptations::CompletionRecorder.new(workout: workout, rpe: 4, completion_quality: :as_planned).call
    snapshot = workout.reload.attributes

    expect { described_class.new(stale).call }.to raise_error(ArgumentError, "Completed workouts cannot be removed")
    expect(workout.reload.attributes).to eq(snapshot)
  end

  it "rejects an archived plan after reloading a stale plan association" do
    workout.training_plan
    TrainingPlan.find(plan.id).update!(status: :archived)

    expect { described_class.new(workout).call }.to raise_error(ArgumentError, /active plan/)
    expect(PlannedWorkout).to exist(workout.id)
  end
end
