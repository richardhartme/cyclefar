require "rails_helper"

RSpec.describe Adaptations::CompletionRecorder, generated_workouts: true do
  let(:today) { Date.new(2026, 10, 5) }
  let(:plan) { create(:training_plan, starts_on: today - 28, ends_on: today + 55, progression_mode: :continuous, hard_weeks_before_recovery: nil) }
  let(:phase) { create(:plan_phase, training_plan: plan, starts_on: plan.starts_on, ends_on: plan.ends_on, kind: :build) }
  let(:profile) { create(:rider_profile, user: plan.user, ftp_watts: 285) }

  before { travel_to today }

  def outline(kind: :workout, date: today - 7, **attributes)
    create(
      :planned_workout,
      training_plan: plan,
      plan_phase: phase,
      scheduled_on: date,
      kind: kind,
      subtype: kind == :opener ? :endurance : :threshold,
      intent: kind == :opener ? :intervals : :threshold,
      progression_level: kind == :opener ? nil : 3,
      duration_minutes: kind == :opener ? 40 : 90,
      variation_key: kind == :opener ? "activation" : "standard",
      **attributes)
  end

  def complete(workout, rpe: 8, quality: :as_planned)
    described_class.new(workout: workout, rpe: rpe, completion_quality: quality).call
  end

  def snapshot(workout)
    [ workout.reload.attributes.deep_dup, workout.workout_steps.reload.map(&:attributes), workout.workout_feedback&.attributes ]
  end

  %i[workout opener].each do |kind|
    it "FBK-001/FBK-003 freezes a late #{kind} outline through FTP, availability and illness replanning" do
      profile
      workout = outline(kind: kind)
      other = outline(date: today - 6)
      future = outline(date: today + 1)
      unaffected = [ other, future ].map { |item| snapshot(item) }

      complete(workout)

      expect(workout.reload).to be_completed
      expect(workout).to be_structured
      expect(workout.completed_ftp_watts).to eq(285)
      expect(workout.workout_steps.sum(:duration_seconds)).to eq(workout.duration_minutes * 60)
      expect(workout.workout_feedback).to have_attributes(rpe: 8, completion_quality: "as_planned")
      expect([ other, future ].map { |item| snapshot(item) }).to eq(unaffected)
      metrics = Metrics::WorkoutCalculator.new(steps: workout.workout_steps, ftp_watts: 285).call
      PlannedWorkout::METRICS.each do |key|
        expect(workout.public_send(key)).to be_within(0.001).of(metrics.public_send(key))
        expect(workout.completed_target_snapshot.fetch(key.to_s).to_f).to be_within(0.001).of(metrics.public_send(key))
      end
      workout.workout_steps.zip(workout.completed_target_snapshot.fetch("steps")).each do |step, target|
        expect(target.fetch("low_watts")).to eq((step.target_low_pct_ftp * 285 / 100).round)
        expect(target.fetch("high_watts")).to eq((step.target_high_pct_ftp * 285 / 100).round)
        if step.ramp?
          expect(target.fetch("end_low_watts")).to eq((step.end_target_low_pct_ftp * 285 / 100).round)
          expect(target.fetch("end_high_watts")).to eq((step.end_target_high_pct_ftp * 285 / 100).round)
        end
      end
      frozen = snapshot(workout)
      slots = [ { weekday: 2, duration_minutes: 60, intent: :endurance } ]
      Settings::Update.new(profile: profile, attributes: { ftp_watts: 320 }).call
      Planning::AvailabilityChanger.new(plan: plan, slots: slots, effective_from: today, scope: :from_date).apply!
      Planning::TimeOffPlanner.new(plan: plan).add!(starts_on: today + 1, ends_on: today + 3, reason: :illness, return_ramp_days: 7)
      expect(snapshot(workout)).to eq(frozen)
      expect { workout.workout_steps.first.update!(label: "Changed") }.to raise_error(ActiveRecord::RecordInvalid, /immutable/)
      expect { workout.workout_feedback.update!(rpe: 1) }.to raise_error(ActiveRecord::RecordInvalid, /immutable/)
    end

    it "FBK-001 rolls back #{kind} structure and metrics when feedback is invalid" do
      workout = outline(kind: kind)
      before = snapshot(workout)
      expect { complete(workout, rpe: 11) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(snapshot(workout)).to eq(before)
    end
  end

  it "FBK-001 completes a structured opener without treating activation as endurance feedback" do
    phase
    workout = Workouts::Creator.new(plan).create!(scheduled_on: today, subtype: :opener, duration_minutes: 30)
    future = generated_workout(plan: plan, phase: phase, date: today + 1, subtype: :endurance)
    before = snapshot(future)
    expect(complete(workout, rpe: 10, quality: :could_not_complete)).to be_nil
    expect(workout.reload).to be_completed
    expect(snapshot(future)).to eq(before)
  end

  it "FBK-001 recalculates overdue structured metrics at the snapshotted current FTP" do
    workout = generated_workout(plan: plan, phase: phase, date: today - 1)
    structure = workout.workout_steps.map(&:attributes)
    profile
    complete(workout)
    expect(workout.reload.completed_ftp_watts).to eq(285)
    expect(workout.workout_steps.reload.map(&:attributes)).to eq(structure)
    metrics = Metrics::WorkoutCalculator.new(steps: workout.workout_steps, ftp_watts: 285).call
    expect(workout.estimated_work_kj).to be_within(0.001).of(metrics.estimated_work_kj)
  end

  it "FBK-003 proposes late feedback only for current targets without rewriting other history" do
    workout = outline
    target = generated_workout(plan: plan, phase: phase, date: today + 1, level: 5, duration: 90)
    distant = outline(date: today + 14)
    before = snapshot(distant)
    proposal = complete(workout, rpe: 10)
    expect(proposal.payload.fetch("changes").map { |change| change.fetch("planned_workout_id") }).to eq([ target.id ])
    frozen = snapshot(workout)
    Adaptations::ProposalApplier.new(proposal).accept!
    expect(target.reload.progression_level).to be < 5
    expect(snapshot(workout)).to eq(frozen)
    expect(snapshot(distant)).to eq(before)
  end

  it "FBK-003 saves late feedback but suppresses adaptation when the next scheduled workout is completed" do
    workout = outline
    completed = create(:planned_workout, :completed, training_plan: plan, plan_phase: phase, scheduled_on: today - 2)
    generated_workout(plan: plan, phase: phase, date: today + 1, level: 5, duration: 90)
    frozen = snapshot(completed)
    expect(complete(workout, rpe: 10)).to be_nil
    expect(workout.reload).to be_completed
    expect(workout.workout_feedback.rpe).to eq(10)
    expect(snapshot(completed)).to eq(frozen)
  end

  it "FBK-003 considers the next scheduled workout rather than every subsequent completed ride" do
    workout = outline
    outline(date: today - 6)
    completed = create(:planned_workout, :completed, training_plan: plan, plan_phase: phase, scheduled_on: today - 2)
    generated_workout(plan: plan, phase: phase, date: today + 1, level: 5, duration: 90)
    frozen = snapshot(completed)
    expect(complete(workout, rpe: 10)).to be_persisted
    expect(snapshot(completed)).to eq(frozen)
  end

  it "FBK-001 keeps FTP tests on their protocol-free completion path" do
    workout = create(:planned_workout, :ftp_test, training_plan: plan, plan_phase: phase, scheduled_on: today - 1)
    before = snapshot(workout)
    expect { complete(workout) }.to raise_error(ArgumentError)
    expect(snapshot(workout)).to eq(before)
  end

  it "FBK-001 rejects future outlines and missed workouts without materialising them" do
    [ outline(date: today + 14), outline(status: :missed) ].each do |workout|
      before = snapshot(workout)
      expect { complete(workout) }.to raise_error(ArgumentError)
      expect(snapshot(workout)).to eq(before)
    end
  end
end
