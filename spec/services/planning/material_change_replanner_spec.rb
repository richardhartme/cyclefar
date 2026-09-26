require "rails_helper"

RSpec.describe Planning::MaterialChangeReplanner, type: :service do
  around { |example| travel_to(Date.new(2026, 9, 7)) { example.run } }

  let(:plan) do
    create(
      :training_plan,
      starts_on: Date.current,
      ends_on: Date.current + 34,
      progression_mode: :continuous,
      hard_weeks_before_recovery: nil)
  end
  let!(:phase) { create(:plan_phase, training_plan: plan, starts_on: plan.starts_on, ends_on: plan.ends_on) }
  let!(:template) { create(:availability_template, training_plan: plan, effective_from: plan.starts_on) }
  let!(:source) do
    create(
      :planned_workout,
      :structured,
      training_plan: plan,
      plan_phase: phase,
      scheduled_on: Date.current + 1,
      intent: :recovery,
      subtype: :recovery,
      name: "Recovery override")
  end
  let!(:replaceable) do
    create(
      :planned_workout,
      :structured,
      training_plan: plan,
      plan_phase: phase,
      scheduled_on: Date.current + 3,
      intent: :threshold,
      subtype: :threshold,
      progression_level: 4)
  end
  let!(:missed) do
    create(
      :planned_workout,
      :structured,
      training_plan: plan,
      plan_phase: phase,
      scheduled_on: Date.current + 5,
      status: :missed)
  end
  let!(:outside_scope) do
    create(
      :planned_workout,
      :structured,
      training_plan: plan,
      plan_phase: phase,
      scheduled_on: Date.current + 20)
  end

  before do
    create(:availability_slot, availability_template: template, weekday: 2, duration_minutes: 60, intent: :intervals)
    create(:availability_slot, availability_template: template, weekday: 4, duration_minutes: 75, intent: :endurance)
    create(:availability_slot, availability_template: template, weekday: 6, duration_minutes: 90, intent: :endurance)
  end

  it "WKO-005 atomically replans the bounded future block while preserving the changed workout and history" do
    source_snapshot = source.attributes.slice("kind", "subtype", "duration_minutes", "name", "estimated_if", "estimated_tss")
    proposal = Planning::MaterialChangeProposal.new(source).replace!(material_change: true)

    Adaptations::ProposalApplier.new(proposal).accept!

    expect(source.reload.attributes.slice(*source_snapshot.keys)).to eq(source_snapshot)
    expect(PlannedWorkout).not_to exist(replaceable.id)
    replacement = plan.planned_workouts.find_by!(scheduled_on: Date.current + 3)
    expect(replacement).to have_attributes(intent: "endurance", duration_minutes: 75)
    expect(missed.reload).to be_missed
    expect(outside_scope.reload).to be_persisted
    expect(AdaptationProposal).not_to exist(proposal.id)
  end

  it "WKO-005 uses the effective availability template for each date" do
    override = create(
      :availability_template,
      training_plan: plan,
      effective_from: Date.current + 7,
      effective_until: Date.current + 13,
      source: :one_week_override)
    create(:availability_slot, availability_template: override, weekday: 4, duration_minutes: 45, intent: :recovery)
    proposal = Planning::MaterialChangeProposal.new(source).replace!(material_change: true)

    Adaptations::ProposalApplier.new(proposal).accept!

    overridden = plan.planned_workouts.find_by!(scheduled_on: Date.current + 10)
    expect(overridden).to have_attributes(subtype: "recovery", duration_minutes: 45)
  end

  it "WKO-005 rolls back the replan when an availability template is missing" do
    template.update!(effective_until: Date.current + 6)
    proposal = Planning::MaterialChangeProposal.new(source).replace!(material_change: true)

    expect do
      Adaptations::ProposalApplier.new(proposal).accept!
    end.to raise_error(ArgumentError, /No availability template/)

    expect(replaceable.reload).to be_persisted
    expect(proposal.reload).to be_persisted
  end
end
