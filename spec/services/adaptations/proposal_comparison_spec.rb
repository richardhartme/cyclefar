require "rails_helper"

RSpec.describe Adaptations::ProposalComparison, type: :service, generated_workouts: true do
  let(:plan) { create(:training_plan, starts_on: Date.current, ends_on: Date.current + 83) }
  let(:phase) { create(:plan_phase, training_plan: plan, ends_on: plan.ends_on) }
  let(:target) { generated_workout(plan: plan, phase: phase, date: Date.current + 2) }

  def proposal_for(changes: nil, bias: 0, source: nil, type: nil)
    payload = { "changes" => changes || [ { "planned_workout_id" => target.id, "progression_level" => 3 } ], "progression_bias" => bias }
    payload["source_workout_id"] = source.id if source
    payload["type"] = type if type
    create(:adaptation_proposal, training_plan: plan, payload: payload, expires_at: 7.days.from_now)
  end

  def canonical_steps(workout)
    workout.workout_steps.reload.map { |step| Workouts::StepDefinition.from(step).to_h }
  end

  it "FBK-002 calculates a stable comparison without changing persisted records" do
    proposal = proposal_for
    before = [ target.attributes, target.workout_steps.map(&:attributes), plan.attributes, proposal.attributes ]
    first = described_class.new(proposal).call
    second = described_class.new(proposal).call
    expect(first.changes.first.preview).to eq(second.changes.first.preview)
    expect(first.changes.first.workout.id).to eq(target.id)
    expect(first.changes.first.preview.definition.progression_level).to eq(2)
    expect([ target.reload.attributes, target.workout_steps.reload.map(&:attributes), plan.reload.attributes, proposal.reload.attributes ]).to eq(before)
  end

  [ nil, "feedback" ].each do |type|
    it "matches acceptance for existing #{type.inspect} feedback payloads" do
      proposal = proposal_for(type: type)
      preview = described_class.new(proposal).call.changes.first.preview
      Adaptations::ProposalApplier.new(proposal).accept!
      expect(target.reload).to have_attributes(
        name: preview.definition.name,
        progression_level: preview.definition.progression_level,
        duration_minutes: preview.definition.duration_minutes,
        variation_key: preview.definition.variation_key)
      expect(canonical_steps(target)).to eq(preview.definition.steps.map(&:to_h))
      PlannedWorkout::METRICS.each do |key|
        expect(target.public_send(key).to_f).to be_within(0.001).of(preview.metrics.public_send(key))
      end
      expect(AdaptationProposal.exists?(proposal.id)).to be(false)
    end
  end

  [ 0, 9 ].each do |requested_level|
    it "shows the fitted effective level for requested level #{requested_level}" do
      short = generated_workout(plan: plan, phase: phase, date: Date.current + 3, duration: 30)
      proposal = proposal_for(changes: [ { "planned_workout_id" => short.id, "progression_level" => requested_level } ])
      preview = described_class.new(proposal).call.changes.first.preview
      expect(preview.definition.requested_progression_level).to eq(requested_level.clamp(1, 7))
      expect(preview.definition.progression_level).to be <= preview.definition.requested_progression_level
      Adaptations::ProposalApplier.new(proposal).accept!
      expect(short.reload.progression_level).to eq(preview.definition.progression_level)
      expect(canonical_steps(short)).to eq(preview.definition.steps.map(&:to_h))
    end
  end

  it "preserves the explicitly selected endurance profile and displays no intensity level" do
    easy = generated_workout(plan: plan, phase: phase, date: Date.current + 4, subtype: :endurance, variation: "undulating")
    proposal = proposal_for(changes: [ { "planned_workout_id" => easy.id, "progression_level" => 1 } ])
    preview = described_class.new(proposal).call.changes.first.preview
    expect(preview.definition.variation_key).to eq("undulating")
    expect(preview.definition.progression_level).to be_nil
    Adaptations::ProposalApplier.new(proposal).accept!
    expect(canonical_steps(easy)).to eq(preview.definition.steps.map(&:to_h))
  end

  it "sorts every affected workout by date" do
    later = generated_workout(plan: plan, phase: phase, date: Date.current + 5)
    proposal = proposal_for(changes: [ later, target ].map { |item| { "planned_workout_id" => item.id, "progression_level" => 2 } })
    expect(described_class.new(proposal).call.changes.map { |change| change.workout.id }).to eq([ target.id, later.id ])
  end

  [ [ 0, 0, 0 ], [ 0, 1, 1 ], [ 0, -1, -1 ], [ 2, 1, 2 ], [ -2, -1, -2 ] ].each do |before, delta, after|
    it "previews and applies bias #{before} + #{delta} as #{after}" do
      plan.update!(progression_state: { "intensity_bias" => before, "other_state" => 3 })
      proposal = proposal_for(bias: delta)
      comparison = described_class.new(proposal).call
      expect(comparison.bias).to have_attributes(before: before, after: after, delta: after - before)
      Adaptations::ProposalApplier.new(proposal).accept!
      expect(plan.reload.progression_state).to eq("intensity_bias" => after, "other_state" => 3)
    end
  end

  it "USR-004 derives both sides at the owning plan's FTP independently of Current.user" do
    create(:rider_profile, user: plan.user, ftp_watts: 275)
    other = create(:user)
    create(:rider_profile, user: other, ftp_watts: 410)
    Current.session = other.sessions.create!
    comparison = described_class.new(proposal_for).call
    expect(comparison.ftp_watts).to eq(275)
    current = Metrics::WorkoutCalculator.new(steps: target.workout_steps, ftp_watts: 275).call
    expect(comparison.changes.first.current_metrics).to eq(current)
    expect(comparison.changes.first.preview.metrics.estimated_work_kj).to be > 0
  ensure
    Current.reset
  end

  [ "source", "target" ].each do |reference|
    it "USR-004 rejects a foreign-plan #{reference} in preview and acceptance" do
      foreign = create(:planned_workout, :structured)
      proposal = if reference == "source"
        proposal_for(source: foreign)
      else
        proposal_for(changes: [ { "planned_workout_id" => foreign.id, "progression_level" => 2 } ])
      end
      before = foreign.attributes
      expect { described_class.new(proposal).call }.to raise_error(ArgumentError, "Proposal is unavailable. Reject it and review your upcoming workouts.")
      expect { Adaptations::ProposalApplier.new(proposal).accept! }.to raise_error(ArgumentError)
      expect(foreign.reload.attributes).to eq(before)
      expect(proposal).to be_persisted
    end
  end

  it "leaves every target and bias unchanged if a later target cannot be applied" do
    completed = create(:planned_workout, :completed, training_plan: plan, plan_phase: phase, scheduled_on: Date.current + 3)
    proposal = proposal_for(bias: -1, changes: [ target, completed ].map { |item| { "planned_workout_id" => item.id, "progression_level" => 2 } })
    before = [ target.attributes, canonical_steps(target), completed.attributes, plan.attributes ]
    expect { Adaptations::ProposalApplier.new(proposal).accept! }.to raise_error(ArgumentError)
    expect([ target.reload.attributes, canonical_steps(target), completed.reload.attributes, plan.reload.attributes ]).to eq(before)
    expect(AdaptationProposal.exists?(proposal.id)).to be(true)
  end

  it "rolls back an earlier edit if a later persistence operation fails" do
    later = generated_workout(plan: plan, phase: phase, date: Date.current + 5)
    proposal = proposal_for(bias: -1, changes: [ target, later ].map { |item| { "planned_workout_id" => item.id, "progression_level" => 2 } })
    before = [ target.attributes, canonical_steps(target), plan.attributes ]
    allow_any_instance_of(Workouts::ManualEditor).to receive(:apply!).and_wrap_original do |original, **args|
      raise ActiveRecord::RecordInvalid.new(later) if original.receiver.instance_variable_get(:@workout).id == later.id
      original.call(**args)
    end
    expect { Adaptations::ProposalApplier.new(proposal).accept! }.to raise_error(ActiveRecord::RecordInvalid)
    expect([ target.reload.attributes, canonical_steps(target), plan.reload.attributes ]).to eq(before)
    expect(AdaptationProposal.exists?(proposal.id)).to be(true)
  end

  it "rejects without changing prescriptions or bias" do
    proposal = proposal_for(bias: 1)
    before = [ target.attributes, canonical_steps(target), plan.attributes ]
    described_class.new(proposal).call
    Adaptations::ProposalApplier.new(proposal).reject!
    expect([ target.reload.attributes, canonical_steps(target), plan.reload.attributes ]).to eq(before)
    expect(AdaptationProposal.exists?(proposal.id)).to be(false)
  end

  it "FBK-002 rechecks the horizon at acceptance after a target moves outside it" do
    proposal = proposal_for
    target.update!(scheduled_on: Date.current + 14)
    before = [ target.attributes, canonical_steps(target), plan.attributes ]
    expect { Adaptations::ProposalApplier.new(proposal).accept! }.to raise_error(ArgumentError)
    expect([ target.reload.attributes, canonical_steps(target), plan.reload.attributes ]).to eq(before)
    expect(proposal.reload).to be_persisted
  end

  it "LOAD-002 shares level ceilings between comparison and acceptance" do
    target.update!(generation_context: { "maximum_level" => 2 })
    proposal = proposal_for(changes: [ { "planned_workout_id" => target.id, "progression_level" => 7 } ])
    comparison = described_class.new(proposal).call
    expect(comparison.changes.first.preview.definition.progression_level).to eq(2)
    Adaptations::ProposalApplier.new(proposal).accept!
    expect(target.reload.progression_level).to eq(2)
    expect(canonical_steps(target)).to eq(comparison.changes.first.preview.definition.steps.map(&:to_h))
  end

  it "LOAD-002 rechecks fixed load added after a proposal was created without changing that fixed workout" do
    plan_with_reference = create(:training_plan, starts_on: Date.current.beginning_of_week - 14, ends_on: Date.current + 83, progression_mode: :continuous, hard_weeks_before_recovery: nil)
    reference_phase = create(:plan_phase, training_plan: plan_with_reference, starts_on: plan_with_reference.starts_on, ends_on: plan_with_reference.ends_on)
    reference = generated_workout(plan: plan_with_reference, phase: reference_phase, date: Date.current.beginning_of_week - 7, level: 5, duration: 90)
    changed = generated_workout(plan: plan_with_reference, phase: reference_phase, date: Date.current, level: 5, duration: 90)
    own_proposal = create(:adaptation_proposal, training_plan: plan_with_reference, payload: { "changes" => [ { "planned_workout_id" => changed.id, "progression_level" => 6 } ] })
    expect(described_class.new(own_proposal).call.changes.first.requested_level).to eq(6)
    fixed = generated_workout(plan: plan_with_reference, phase: reference_phase, date: Date.current + 1, subtype: :recovery, duration: 30)
    before = [ fixed.attributes, canonical_steps(fixed) ]
    comparison = described_class.new(own_proposal).call
    expect(comparison.changes.first.preview.metrics.estimated_tss + fixed.estimated_tss).to be <= reference.estimated_tss * 1.08
    Adaptations::ProposalApplier.new(own_proposal).accept!
    expect(changed.reload.estimated_tss + fixed.estimated_tss).to be <= reference.estimated_tss * 1.08
    expect([ fixed.reload.attributes, canonical_steps(fixed) ]).to eq(before)
  end
end
