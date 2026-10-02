require "rails_helper"

RSpec.describe Adaptations::FeedbackEvaluator, generated_workouts: true do
  let(:today) { Date.new(2026, 10, 5) }
  let(:plan) { create(:training_plan, starts_on: today - 28, ends_on: today + 83, progression_mode: :continuous, hard_weeks_before_recovery: nil) }
  let(:phase) { create(:plan_phase, training_plan: plan, starts_on: plan.starts_on, ends_on: plan.ends_on, kind: :build) }
  let(:source) { ride(today, level: 4) }

  before { travel_to today }

  def ride(date, subtype: :threshold, level: 4, intent: (subtype == :over_under ? :intervals : subtype))
    workout = generated_workout(plan: plan, phase: phase, date: date, subtype: (subtype == :over_under ? :vo2_max : subtype), level: level, duration: 90)
    Workouts::ManualEditor.new(workout).apply!(action: :change, subtype: :over_under, duration_minutes: 90) if subtype == :over_under
    workout.update!(intent: intent)
    workout
  end

  def complete(workout = source, quality: :as_planned, rpe: 10)
    Adaptations::CompletionRecorder.new(workout: workout, rpe: rpe, completion_quality: quality).call
  end

  def levels(proposal)
    proposal.payload.fetch("changes").to_h { |change| [ change.fetch("planned_workout_id"), change.fetch("progression_level") ] }
  end

  def snapshot(workout)
    [ workout.reload.attributes, workout.workout_steps.reload.map(&:attributes) ]
  end

  it "FBK-002 includes day 13 but excludes structured day 14 and completed, missed, overdue and outline rides" do
    last = ride(today + 13)
    distant = ride(today + 14)
    overdue = ride(today - 1)
    missed = ride(today + 1)
    missed.update!(status: :missed)
    create(:planned_workout, :completed, training_plan: plan, plan_phase: phase, scheduled_on: today + 2, subtype: :threshold)
    create(:planned_workout, training_plan: plan, plan_phase: phase, scheduled_on: today + 3, subtype: :threshold, progression_level: 4)
    before = [ distant, overdue, missed ].map { |workout| snapshot(workout) }
    proposal = complete
    expect(levels(proposal)).to eq(last.id => 2)
    Adaptations::ProposalApplier.new(proposal).accept!
    expect([ distant, overdue, missed ].map { |workout| snapshot(workout) }).to eq(before)
  end

  it "FBK-002 produces no adaptation for a same-subtype ride beyond the horizon" do
    ride(today + 14)
    expect(complete).to be_nil
    expect(source.reload).to be_completed
  end

  it "FBK-002 prefers the same subtype over an earlier family fallback" do
    ride(today + 1, subtype: :sweet_spot)
    target = ride(today + 4)
    expect(levels(complete)).to eq(target.id => 2)
  end

  [ [ :threshold, :sweet_spot ], [ :vo2_max, :over_under ] ].each do |subtype, fallback|
    it "FBK-002 falls back from #{subtype} to #{fallback} while preserving the target's explicit intent" do
      workout = ride(today, subtype: subtype)
      easy = ride(today + 1, subtype: :endurance)
      target = ride(today + 2, subtype: fallback)
      easy_before = snapshot(easy)
      proposal = complete(workout, quality: :struggled_completed)
      expect(levels(proposal)).to eq(target.id => 3)
      Adaptations::ProposalApplier.new(proposal).accept!
      expect(target.reload).to have_attributes(subtype: fallback.to_s, intent: (fallback == :over_under ? "intervals" : fallback.to_s), duration_minutes: 90)
      expect(snapshot(easy)).to eq(easy_before)
    end
  end

  it "FBK-002 allows cross-family fallback only for an engine-selected broad interval source" do
    source.update!(intent: :intervals)
    target = ride(today + 3, subtype: :vo2_max, intent: :intervals)
    expect(levels(complete)).to eq(target.id => 3)
  end

  it "FBK-002 does not use cross-family fallback for an explicitly selected subtype" do
    ride(today + 3, subtype: :vo2_max, intent: :intervals)
    expect(complete).to be_nil
  end

  it "FBK-002 reduces broad hard sessions within 48 hours after struggling, retaining specific unrelated hard days" do
    broad = ride(today + 1, subtype: :vo2_max, intent: :intervals)
    specific = ride(today + 2, subtype: :vo2_max)
    beyond = ride(today + 3, subtype: :vo2_max, intent: :intervals)
    target = ride(today + 5)
    before = [ specific, beyond ].map { |workout| snapshot(workout) }
    proposal = complete(quality: :struggled_completed)
    expect(levels(proposal)).to eq(broad.id => 3, target.id => 2)
    Adaptations::ProposalApplier.new(proposal).accept!
    expect(broad.reload.intent).to eq("intervals")
    expect([ specific, beyond ].map { |workout| snapshot(workout) }).to eq(before)
  end

  it "FBK-002 reduces every nearby hard session after failure without stacking reductions" do
    nearest = ride(today + 1)
    nearby = ride(today + 2, subtype: :vo2_max)
    beyond = ride(today + 3, subtype: :vo2_max)
    proposal = complete(quality: :could_not_complete)
    expect(levels(proposal)).to eq(nearest.id => 2, nearby.id => 3)
    completed_before = snapshot(source)
    Adaptations::ProposalApplier.new(proposal).accept!
    expect(snapshot(source)).to eq(completed_before)
    expect(beyond.reload.progression_level).to eq(4)
  end

  %i[recovery endurance].each do |subtype|
    it "FBK-002 lowers high-RPE #{subtype} targets with nil levels without introducing intensity" do
      workout = ride(today, subtype: subtype)
      target = ride(today + 1, subtype: subtype)
      hard = ride(today + 2)
      before = snapshot(target)
      hard_before = snapshot(hard)
      proposal = complete(workout, rpe: 8)
      expect(proposal.payload.fetch("changes").first.fetch("lower_targets")).to be(true)
      expect(proposal.payload.fetch("progression_bias")).to eq(0)
      comparison = Adaptations::ProposalComparison.new(proposal).call
      expect(comparison.changes.first.preview.definition.progression_level).to be_nil
      expect(comparison.changes.first.preview.metrics.estimated_tss).to be < target.estimated_tss
      expect(snapshot(target)).to eq(before)
      Adaptations::ProposalApplier.new(proposal).accept!
      expect(target.reload).to have_attributes(subtype: subtype.to_s, intent: subtype.to_s, progression_level: nil, duration_minutes: 90)
      expect(target.workout_steps.map(&:target_high_pct_ftp).max).to be <= (subtype == :recovery ? 55 : 75)
      expect(snapshot(hard)).to eq(hard_before)
    end

    it "FBK-002 ignores unusually low #{subtype} RPE" do
      workout = ride(today, subtype: subtype)
      ride(today + 1, subtype: subtype)
      expect(complete(workout, rpe: 1)).to be_nil
    end
  end

  it "FBK-002 preserves completion even when no lower intensity prescription fits" do
    source.update!(progression_level: 1)
    ride(today + 1, level: 1)
    expect(complete(quality: :could_not_complete)).to be_nil
    expect(source.reload).to be_completed
  end

  it "LOAD-002 suppresses a too-easy increase when it would exceed the comparable hard-week cap" do
    target = ride(today + 7, level: 5)
    before = snapshot(target)
    expect(complete(rpe: 1)).to be_nil
    expect(snapshot(target)).to eq(before)
  end

  it "LOAD-002 permits a too-easy increase when the generated week remains within the cap" do
    source = ride(today, level: 5)
    target = ride(today + 7, level: 5)
    proposal = complete(source, rpe: 1)
    expect(levels(proposal)).to eq(target.id => 6)
    Adaptations::ProposalApplier.new(proposal).accept!
    expect(target.reload.estimated_tss).to be <= source.estimated_tss * 1.08
  end

  it "FBK-002 ignores normal intensity feedback" do
    ride(today + 1)
    expect(complete(rpe: 8)).to be_nil
  end

  it "FBK-002 evaluates the most recent three feedbacks by scheduled date rather than insertion order" do
    complete(ride(today - 2), quality: :struggled_completed, rpe: 9)
    complete(ride(today - 1), rpe: 8)
    complete(ride(today - 20), rpe: 1)
    ride(today + 1, level: 5)
    proposal = complete
    expect(proposal.payload.fetch("progression_bias")).to eq(-1)
    expect(plan.reload.progression_state).to eq({})
    Adaptations::ProposalApplier.new(proposal).accept!
    expect(plan.reload.progression_state).to eq("intensity_bias" => -1)
  end

  it "FBK-003 blocks late feedback after another later scheduled ride is completed" do
    old = ride(today - 7)
    create(:planned_workout, :completed, training_plan: plan, plan_phase: phase, scheduled_on: today - 2)
    ride(today + 2)
    expect(complete(old)).to be_nil
    expect(old.reload).to be_completed
  end
end
