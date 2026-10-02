require "rails_helper"

RSpec.describe "FBK-002 / USR-004 feedback ownership", generated_workouts: true do
  let(:today) { Date.new(2026, 10, 5) }
  let(:plan) { create(:training_plan, starts_on: today - 28, ends_on: today + 83, progression_mode: :continuous, hard_weeks_before_recovery: nil) }
  let(:phase) { create(:plan_phase, training_plan: plan, starts_on: plan.starts_on, ends_on: plan.ends_on, kind: :build) }
  let(:other_plan) { create(:training_plan, starts_on: plan.starts_on, ends_on: plan.ends_on, progression_state: { "intensity_bias" => 2 }) }
  let(:other_phase) { create(:plan_phase, training_plan: other_plan, starts_on: other_plan.starts_on, ends_on: other_plan.ends_on, kind: :build) }

  before { travel_to today }
  after { Current.reset }

  def record(workout, rpe: 10)
    Adaptations::CompletionRecorder.new(workout: workout, rpe: rpe, completion_quality: :as_planned).call
  end

  def state(owner_plan)
    [ owner_plan.reload.attributes,
      owner_plan.user.rider_profile&.reload&.attributes,
      owner_plan.planned_workouts.order(:id).map { |workout| [ workout.attributes, workout.workout_steps.map(&:attributes), workout.workout_feedback&.attributes ] },
      owner_plan.adaptation_proposals.order(:id).map(&:attributes) ]
  end

  it "uses only the source plan for target selection, feedback patterns and accepted bias" do
    create(:rider_profile, user: other_plan.user, ftp_watts: 410)
    # Another rider has earlier matching targets and sufficient hard feedback
    # to form a pattern; neither should influence this rider's evaluation.
    [ today - 2, today - 1 ].each do |date|
      record(generated_workout(plan: other_plan, phase: other_phase, date: date, duration: 90))
    end
    generated_workout(plan: other_plan, phase: other_phase, date: today + 1, level: 5, duration: 90)
    foreign_target = generated_workout(plan: other_plan, phase: other_phase, date: today + 2, level: 5, duration: 90)
    create(:adaptation_proposal, training_plan: other_plan, payload: { "changes" => [ { "planned_workout_id" => foreign_target.id, "progression_level" => 4 } ] })
    source = generated_workout(plan: plan, phase: phase, date: today, duration: 90)
    target = generated_workout(plan: plan, phase: phase, date: today + 3, level: 5, duration: 90)
    other_before = state(other_plan)
    Current.session = other_plan.user.sessions.create!

    proposal = record(source)
    expect(proposal.training_plan_id).to eq(plan.id)
    expect(proposal.payload.fetch("changes").pluck("planned_workout_id")).to eq([ target.id ])
    expect(proposal.payload.fetch("progression_bias")).to eq(0)
    source_before = [ source.reload.attributes, source.workout_steps.map(&:attributes), source.workout_feedback.attributes ]
    Adaptations::ProposalApplier.new(proposal).accept!
    expect(target.reload.progression_level).to eq(4)
    expect(plan.reload.progression_state).to eq({})
    expect(state(other_plan)).to eq(other_before)
    expect([ source.reload.attributes, source.workout_steps.reload.map(&:attributes), source.workout_feedback.reload.attributes ]).to eq(source_before)
  end

  it "keeps another rider's weekly load out of this plan's cap reference" do
    create(:rider_profile, user: other_plan.user, ftp_watts: 410)
    generated_workout(plan: other_plan, phase: other_phase, date: today, subtype: :recovery, duration: 30)
    generated_workout(plan: other_plan, phase: other_phase, date: today + 7, duration: 120)
    source = generated_workout(plan: plan, phase: phase, date: today, level: 5, duration: 90)
    target = generated_workout(plan: plan, phase: phase, date: today + 7, level: 5, duration: 90)
    other_before = state(other_plan)
    Current.session = other_plan.user.sessions.create!

    proposal = record(source, rpe: 1)
    comparison = Adaptations::ProposalComparison.new(proposal).call
    expect(comparison.changes.first.requested_level).to eq(6)
    Adaptations::ProposalApplier.new(proposal).accept!
    expect(target.reload.progression_level).to eq(6)
    expect(target.estimated_tss).to be <= source.estimated_tss * 1.08
    expect(state(other_plan)).to eq(other_before)
  end

  [ nil, 285 ].each do |ftp|
    it "previews and accepts with #{ftp ? 'the owner profile FTP' : 'the plan initial FTP fallback'} despite another Current.user" do
      create(:rider_profile, user: plan.user, ftp_watts: ftp) if ftp
      create(:rider_profile, user: other_plan.user, ftp_watts: 410)
      history = create(:planned_workout, :completed, training_plan: other_plan, plan_phase: other_phase, scheduled_on: today - 1)
      target = generated_workout(plan: plan, phase: phase, date: today + 2, level: 5, duration: 90)
      proposal = create(
        :adaptation_proposal,
        training_plan: plan,
        payload: { "changes" => [ { "planned_workout_id" => target.id, "progression_level" => 4 } ], "progression_bias" => -1 })
      other_before = state(other_plan)
      Current.session = other_plan.user.sessions.create!
      basis = ftp || plan.initial_ftp_watts
      comparison = Adaptations::ProposalComparison.new(proposal).call
      expect(comparison.ftp_watts).to eq(basis)
      expected = Metrics::WorkoutCalculator.new(steps: comparison.changes.first.preview.definition.steps, ftp_watts: basis).call
      expect(comparison.changes.first.preview.metrics).to eq(expected)

      Adaptations::ProposalApplier.new(proposal).accept!
      target.reload
      PlannedWorkout::METRICS.each do |metric|
        expect(target.public_send(metric).to_f).to be_within(0.001).of(expected.public_send(metric))
      end
      expect(plan.reload.progression_state).to eq("intensity_bias" => -1)
      expect(state(other_plan)).to eq(other_before)
      expect(history.reload.completed_ftp_watts).to eq(260)
    end
  end
end
