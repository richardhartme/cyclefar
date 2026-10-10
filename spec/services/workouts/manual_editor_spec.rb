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

  it "WKO-004 adjusts only the selected workout's load for easier and harder" do
    initial_tss = workout.estimated_tss
    described_class.new(workout).apply!(action: :harder)
    expect(workout.reload.estimated_tss.round).to be > initial_tss.round
    harder_tss = workout.estimated_tss
    described_class.new(workout).apply!(action: :easier)
    expect(workout.reload.estimated_tss.round).to be < harder_tss.round
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

RSpec.describe Workouts::ManualEditor, type: :service, generated_workouts: true do
  let(:plan) { create(:training_plan, progression_mode: :continuous, hard_weeks_before_recovery: nil) }
  let(:phase) { create(:plan_phase, training_plan: plan, ends_on: plan.ends_on) }
  let(:workout) { generated_workout(plan: plan, phase: phase, date: plan.starts_on + 1, subtype: :over_under, level: 3) }

  def persisted_state(target)
    [ target.reload.attributes, target.workout_steps.reload.map(&:attributes) ]
  end

  it "WKO-004 previews the canonical load reduction without persistence, then applies the same replacement" do
    before = persisted_state(workout)
    preview = described_class.new(workout).preview(action: :easier)
    expect(persisted_state(workout)).to eq(before)
    expect(preview.definition.progression_level).to eq(1)
    expect(preview.before.estimated_tss).to be_within(0.001).of(64.186)
    result = described_class.new(workout).apply!(action: :easier)
    expect(result.after).to eq(preview.after)
    expect(workout.reload.name).to eq("Over-Unders 2x9")
    expect(workout.workout_steps.map { |step| Workouts::StepDefinition.from(step) }).to eq(preview.definition.steps)
  end

  it "WKO-004 uses canonical steps rather than stale stored metrics to choose direction" do
    workout.update!(estimated_tss: 1, estimated_if: 0.1)
    result = described_class.new(workout).apply!(action: :easier)
    expect(result.before.estimated_tss).to be_within(0.001).of(64.186)
    expect(result.after.estimated_tss).to be_within(0.001).of(59.377)
  end

  [ :easier, :harder ].each do |action|
    it "WKO-004 persists no changes when #{action} reaches the limit" do
      recovery = generated_workout(plan: plan, phase: phase, date: plan.starts_on + 2, subtype: :recovery)
      before = persisted_state(recovery)
      expect { described_class.new(recovery).apply!(action: action) }.to raise_error(ArgumentError, /No .*load option/)
      expect(persisted_state(recovery)).to eq(before)
    end
  end

  it "WKO-004 repeatedly adjusts persisted endurance load without wrapping profiles" do
    endurance = generated_workout(plan: plan, phase: phase, date: plan.starts_on + 2, subtype: :endurance, variation: "alternating")
    described_class.new(endurance).apply!(action: :easier)
    expect(endurance.reload).to have_attributes(variation_key: "sustained", progression_level: nil)
    expect(endurance.estimated_tss.round).to eq(44)
    before = persisted_state(endurance)
    expect { described_class.new(endurance).apply!(action: :easier) }.to raise_error(ArgumentError, /No lower-load option/)
    expect(persisted_state(endurance)).to eq(before)
    described_class.new(endurance).apply!(action: :harder)
    expect(endurance.reload).to have_attributes(variation_key: "alternating", progression_level: nil)
    expect(endurance.estimated_tss.round).to eq(45)
    before = persisted_state(endurance)
    expect { described_class.new(endurance).apply!(action: :harder) }.to raise_error(ArgumentError, /No higher-load option/)
    expect(persisted_state(endurance)).to eq(before)
  end

  it "WKO-004 retains saved generation constraints and automatic references when increasing load" do
    adjusted = generated_workout(
      plan: plan,
      phase: phase,
      date: plan.starts_on + 2,
      subtype: :sweet_spot,
      level: 1,
      duration: 90,
      load_adjustments: { "main_set_factor" => 0.6, "lower_targets" => true, "return_target_band" => [ 55, 87 ] })
    adjusted.update!(
      generation_context: adjusted.generation_context.merge(
        "maximum_level" => 2, "generated_level" => 1, "generated_tss" => adjusted.estimated_tss.to_f, "baseline_level" => 4))
    original_context = adjusted.generation_context.deep_dup
    described_class.new(adjusted).apply!(action: :harder)
    expect(adjusted.reload.progression_level).to eq(2)
    expect(adjusted.generation_context).to eq(original_context)
    expect(adjusted.workout_steps.map(&:target_high_pct_ftp)).to all(be <= 87)
    expect(adjusted.workout_steps.filter_map(&:end_target_high_pct_ftp)).to all(be <= 87)
    expect(adjusted.workout_steps.sum(:duration_seconds)).to eq(5400)
    before = persisted_state(adjusted)
    expect { described_class.new(adjusted).apply!(action: :harder) }.to raise_error(ArgumentError, /No higher-load option/)
    expect(persisted_state(adjusted)).to eq(before)
  end

  it "WKO-004 honours the reduced-period ceiling even without a saved maximum" do
    create(:time_off_period, training_plan: plan, reason: :illness, starts_on: plan.starts_on, ends_on: plan.starts_on, return_ramp_days: 7)
    before = persisted_state(workout)
    expect { described_class.new(workout).apply!(action: :harder) }.to raise_error(ArgumentError, /No higher-load option/)
    expect(persisted_state(workout)).to eq(before)
  end

  it "WKO-004 leaves other prescriptions, completed history and plan progression unchanged" do
    other = generated_workout(plan: plan, phase: phase, date: plan.starts_on + 2)
    completed = create(:planned_workout, :completed, training_plan: plan, plan_phase: phase, scheduled_on: plan.starts_on + 3)
    before = [ persisted_state(other), persisted_state(completed), plan.reload.attributes ]
    described_class.new(workout).apply!(action: :easier)
    expect([ persisted_state(other), persisted_state(completed), plan.reload.attributes ]).to eq(before)
    expect(plan.adaptation_proposals).to be_empty
    [ :easier, :harder ].each do |action|
      expect { described_class.new(completed).apply!(action: action) }.to raise_error(ArgumentError, /Only planned structured workouts/)
    end
  end
end
