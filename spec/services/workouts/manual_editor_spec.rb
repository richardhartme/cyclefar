require "rails_helper"

RSpec.describe Workouts::ManualEditor, type: :service do
  let(:plan) { create(:training_plan) }
  let(:phase) { create(:plan_phase, training_plan: plan, ends_on: plan.ends_on) }
  let(:workout) { create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, subtype: :threshold, intent: :threshold, progression_level: 3, variation_key: "standard", scheduled_on: plan.starts_on + 1) }

  before do
    definition = Workouts::Generator.new(subtype: :threshold, duration_minutes: 60, progression_level: 3, phase: :base, goal: :increase_ftp, discipline: :road, variation_key: "standard").call
    metrics = Metrics::WorkoutCalculator.new(steps: definition.steps, ftp_watts: plan.initial_ftp_watts).call
    workout.workout_steps.destroy_all
    workout.assign_attributes(name: definition.name, purpose: definition.purpose, estimated_np_watts: metrics.estimated_np_watts, estimated_if: metrics.estimated_if, estimated_tss: metrics.estimated_tss, estimated_work_kj: metrics.estimated_work_kj)
    definition.steps.each { |step| workout.workout_steps.build(step.to_h) }
    workout.save!
  end

  it "WKO-004 shuffles Same deterministically while preserving subtype, duration and approximate load" do
    before = workout.estimated_tss
    described_class.new(workout).apply!(action: :same)
    expect(workout.reload).to have_attributes(subtype: "threshold", duration_minutes: 60, variation_key: "redistributed_recovery")
    expect((workout.estimated_tss / before - 1).abs).to be <= 0.05
    expect(workout.workout_steps.sum(:duration_seconds)).to eq(3600)
  end

  it "WKO-004 adjusts only the selected workout's level for easier and harder" do
    described_class.new(workout).apply!(action: :harder)
    expect(workout.reload.progression_level).to eq(4)
    described_class.new(workout).apply!(action: :easier)
    expect(workout.reload.progression_level).to eq(3)
    expect(plan.reload.progression_state).to eq({})
  end

  it "recalculates edits from the workout owner's FTP with another rider present" do
    other_plan = create(:training_plan)
    other_profile = create(:rider_profile, user: other_plan.user, ftp_watts: 410)
    create(:rider_profile, user: plan.user, ftp_watts: 290)

    described_class.new(workout).apply!(action: :easier)

    expected = Metrics::WorkoutCalculator.new(steps: workout.reload.workout_steps, ftp_watts: 290).call
    expect(workout.estimated_np_watts).to be_within(0.001).of(expected.estimated_np_watts)
    expect(workout.estimated_work_kj).to be_within(0.001).of(expected.estimated_work_kj)
    expect(other_profile.reload.ftp_watts).to eq(410)
  end

  it "WKO-004 enforces the 30 minute minimum and regenerates exact 15 minute changes" do
    described_class.new(workout).apply!(action: :shorter)
    expect(workout.reload.duration_minutes).to eq(45)
    described_class.new(workout).apply!(action: :shorter)
    expect(workout.reload.duration_minutes).to eq(30)
    expect { described_class.new(workout).apply!(action: :shorter) }.to raise_error(ArgumentError, /below 30/)
    described_class.new(workout).apply!(action: :longer)
    expect(workout.reload.duration_minutes).to eq(45)
  end

  it "WKO-005 changes subtype and exposes material changes without a replan" do
    result = described_class.new(workout).apply!(action: :change, subtype: :recovery, duration_minutes: 60)
    expect(result.material_change).to be(true)
    expect(result.before).to have_attributes(kind: "workout", subtype: "threshold")
    expect(result.after).to have_attributes(kind: "workout", subtype: "recovery")
    expect(workout.reload.subtype).to eq("recovery")
    expect(plan.planned_workouts.where.not(id: workout.id).count).to eq(0)
  end

  it "WKO-005 uses the documented material-change thresholds" do
    editor = described_class.new(workout)
    before = described_class::Snapshot.new(
      kind: "workout", subtype: "threshold", duration_minutes: 60, estimated_if: "0.80".to_d, estimated_tss: 100.to_d)

    expect(editor.send(:material_change?, before, before.with(estimated_tss: 115.to_d))).to be(true)
    expect(editor.send(:material_change?, before, before.with(estimated_if: "0.88".to_d))).to be(true)
    expect(editor.send(:material_change?, before, before.with(subtype: "endurance"))).to be(true)
    expect(editor.send(:material_change?, before, before.with(estimated_tss: "114.9".to_d, estimated_if: "0.879".to_d))).to be(false)
  end

  it "WKO-005 changes a regular workout to the canonical 30–45 minute opener" do
    result = described_class.new(workout).apply!(
      action: :change,
      subtype: :opener,
      duration_minutes: 45)

    expect(result.material_change).to be(true)
    expect(workout.reload).to have_attributes(
      kind: "opener",
      intent: "intervals",
      subtype: "endurance",
      duration_minutes: 45,
      progression_level: nil,
      name: "Event Opener")
    expect(workout.workout_steps.map(&:label)).to include("Threshold activation", "VO2 activation")
  end

  it "WKO-005 rejects an opener longer than 45 minutes" do
    expect do
      described_class.new(workout).apply!(
        action: :change,
        subtype: :opener,
        duration_minutes: 60)
    end.to raise_error(ArgumentError, "opener duration must be 30 to 45 minutes")
  end
end
