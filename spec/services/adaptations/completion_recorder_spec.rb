require "rails_helper"

RSpec.describe Adaptations::CompletionRecorder, type: :service do
  let(:plan) { create(:training_plan, starts_on: Date.current, ends_on: Date.current + 83) }
  let(:phase) { create(:plan_phase, training_plan: plan, ends_on: plan.ends_on) }
  let(:workout) { create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, subtype: :threshold, intent: :threshold, progression_level: 3, scheduled_on: plan.starts_on) }

  it "FBK-001 atomically records feedback and an immutable completion snapshot" do
    other_plan = create(:training_plan, starts_on: plan.starts_on, ends_on: plan.ends_on)
    other_phase = create(:plan_phase, training_plan: other_plan, starts_on: other_plan.starts_on, ends_on: other_plan.ends_on)
    other_workout = create(:planned_workout, :structured, training_plan: other_plan, plan_phase: other_phase, scheduled_on: plan.starts_on)
    other_attributes = other_workout.attributes.deep_dup
    other_profile = create(:rider_profile, user: other_plan.user, ftp_watts: 410, intervals_icu_api_key: "other-rider-secret")
    create(:rider_profile, user: plan.user, ftp_watts: 275)
    expect { described_class.new(workout: workout, rpe: 8, completion_quality: :as_planned).call }.to change(WorkoutFeedback, :count).by(1)
    expect(workout.reload).to be_completed
    expect(workout.completed_ftp_watts).to eq(275)
    expect(workout.completed_target_snapshot.fetch("steps")).not_to be_empty
    first_step = workout.workout_steps.first
    first_target = workout.completed_target_snapshot.fetch("steps").first
    expect(first_target.fetch("low_watts")).to eq((first_step.target_low_pct_ftp * 275 / 100).round)
    expect { workout.update!(name: "Changed") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect(other_workout.reload.attributes).to eq(other_attributes)
    expect(other_profile.reload).to have_attributes(ftp_watts: 410, intervals_icu_api_key: "other-rider-secret")
  end

  it "FBK-002 creates a proposal but does not alter future workouts before acceptance" do
    next_workout = create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, subtype: :threshold, intent: :threshold, progression_level: 4, scheduled_on: plan.starts_on + 2)
    proposal = described_class.new(workout: workout, rpe: 10, completion_quality: :as_planned).call
    expect(proposal).to be_persisted
    expect(next_workout.reload.progression_level).to eq(4)
    Adaptations::ProposalApplier.new(proposal).accept!
    expect(next_workout.reload.progression_level).to eq(3)
    expect(AdaptationProposal).not_to exist(proposal.id)
  end

  it "FBK-002 rejection is a no-op for workouts" do
    next_workout = create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, subtype: :threshold, intent: :threshold, progression_level: 4, scheduled_on: plan.starts_on + 2)
    proposal = described_class.new(workout: workout, rpe: 10, completion_quality: :as_planned).call
    Adaptations::ProposalApplier.new(proposal).reject!
    expect(next_workout.reload.progression_level).to eq(4)
    expect(AdaptationProposal).not_to exist(proposal.id)
  end
end
