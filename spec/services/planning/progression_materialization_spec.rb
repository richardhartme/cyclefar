require "rails_helper"

RSpec.describe Planning::HorizonMaterializer, generated_workouts: true do
  let(:today) { Date.new(2026, 10, 5) }
  let(:plan) { create(:training_plan, starts_on: today, ends_on: today + 83, progression_mode: :continuous, hard_weeks_before_recovery: nil) }
  let(:phase) { create(:plan_phase, training_plan: plan, starts_on: plan.starts_on, ends_on: plan.ends_on, kind: :build) }

  before { travel_to today }

  def outline(date: today, level: 3, duration: 90, subtype: :threshold, **attributes)
    create(
      :planned_workout,
      training_plan: plan,
      plan_phase: phase,
      scheduled_on: date,
      intent: subtype,
      subtype: subtype,
      progression_level: level,
      duration_minutes: duration,
      variation_key: Workouts::Variations.default_key(subtype),
**attributes)
  end

  def steps(workout)
    workout.workout_steps.reload.map { |step| Workouts::StepDefinition.from(step).to_h }
  end

  [ -2, -1, 0, 1, 2 ].each do |bias|
    it "FBK-002 consumes accepted bias #{bias} using the owning plan's FTP" do
      create(:rider_profile, user: plan.user, ftp_watts: 285)
      plan.update!(progression_state: { "intensity_bias" => bias })
      workout = outline
      described_class.new(plan).call
      expected = Workouts::Generator.new(subtype: :threshold, duration_minutes: 90, progression_level: 3 + bias, phase: :build).call
      expect(workout.reload.progression_level).to eq(expected.progression_level)
      expect(steps(workout)).to eq(expected.steps.map(&:to_h))
      metrics = Metrics::WorkoutCalculator.new(steps: expected.steps, ftp_watts: 285).call
      expect(workout.estimated_work_kj).to be_within(0.001).of(metrics.estimated_work_kj)
    end
  end

  it "FBK-002 applies an accepted proposal only when an outline enters the horizon" do
    target = generated_workout(plan: plan, phase: phase, date: today + 1, level: 3, duration: 90)
    future = outline(date: today + 14)
    proposal = create(
      :adaptation_proposal,
      training_plan: plan,
      payload: {
            "changes" => [ { "planned_workout_id" => target.id, "progression_level" => 2 } ], "progression_bias" => -1 })
    described_class.new(plan).call
    expect(future.reload).to be_outline
    Adaptations::ProposalApplier.new(proposal).accept!
    target_steps = steps(target)
    expect(future.reload.progression_level).to eq(3)
    described_class.new(plan, date: today + 1).call
    expect(future.reload.progression_level).to eq(2)
    expect(steps(target)).to eq(target_steps)
    expect(plan.reload.progression_state).to eq("intensity_bias" => -1)
  end

  it "FBK-002 leaves pending and rejected bias unapplied" do
    target = generated_workout(plan: plan, phase: phase, date: today + 1, duration: 90)
    future = outline(date: today + 14)
    proposal = create(:adaptation_proposal, training_plan: plan, payload: { "changes" => [], "progression_bias" => -1 })
    described_class.new(plan).call
    Adaptations::ProposalApplier.new(proposal).reject!
    described_class.new(plan, date: today + 1).call
    expect(future.reload.progression_level).to eq(3)
    expect(plan.reload.progression_state).to eq({})
    expect(target.reload).to be_structured
  end

  it "GEN-001 persists the fitted effective level and never reapplies bias" do
    plan.update!(progression_state: { "intensity_bias" => 2 })
    workout = outline(level: 7, duration: 30)
    described_class.new(plan).call
    expected = Workouts::Generator.new(subtype: :threshold, duration_minutes: 30, progression_level: 7).call
    expect(workout.reload.progression_level).to eq(expected.progression_level)
    snapshot = [ workout.attributes, steps(workout) ]
    described_class.new(plan).call
    expect([ workout.reload.attributes, steps(workout) ]).to eq(snapshot)
  end
  it "GEN-001 includes today and day 13 while leaving overdue, missed and day 14 outlines alone" do
    first = outline
    last = outline(date: today + 13)
    future = outline(date: today + 14)
    missed = outline(date: today + 2, status: :missed)
    plan.update!(progression_state: { "intensity_bias" => -1 })
    described_class.new(plan).call
    expect([ first.reload.progression_level, last.reload.progression_level ]).to eq([ 2, 2 ])
    expect([ future.reload.detail_status, missed.reload.detail_status ]).to eq(%w[outline outline])
  end

  it "does not assign intensity levels to endurance, recovery, opener or FTP Test" do
    plan.update!(progression_state: { "intensity_bias" => 2 })
    easy = outline(subtype: :endurance, level: nil)
    recovery = outline(date: today + 1, subtype: :recovery, level: nil)
    opener = outline(date: today + 2, kind: :opener, subtype: :endurance, level: nil, duration: 30, variation_key: "activation")
    test = create(:planned_workout, :ftp_test, training_plan: plan, plan_phase: phase, scheduled_on: today + 3)
    described_class.new(plan).call
    expect([ easy, recovery, opener ].map { |workout| workout.reload.progression_level }).to eq([ nil, nil, nil ])
    expect(test.reload).to be_outline
  end

  it "preserves a load-limited outline ceiling and the generated effective level" do
    plan.update!(progression_state: { "intensity_bias" => 2 })
    workout = outline(level: 2, generation_context: { "maximum_level" => 2 })
    described_class.new(plan).call
    expect(workout.reload.progression_level).to eq(2)
  end

  it "reads freshly accepted state even when the caller holds an old plan instance" do
    workout = outline
    TrainingPlan.find(plan.id).update!(progression_state: { "intensity_bias" => -2 })
    described_class.new(plan).call
    expect(workout.reload.progression_level).to eq(1)
  end

  it "rolls back all structures and steps if a later save fails" do
    first = outline
    later = outline(date: today + 1)
    allow_any_instance_of(PlannedWorkout).to receive(:save!).and_wrap_original do |original, *args|
      raise ActiveRecord::RecordInvalid.new(later) if original.receiver.id == later.id
      original.call(*args)
    end
    expect { described_class.new(plan).call }.to raise_error(ActiveRecord::RecordInvalid)
    expect(first.reload).to be_outline
    expect(first.workout_steps).to be_empty
    expect(later.reload).to be_outline
    expect(later.workout_steps).to be_empty
  end

  context "with previous hard weeks" do
    let(:plan) { create(:training_plan, starts_on: today - 28, ends_on: today + 83, progression_mode: :continuous, hard_weeks_before_recovery: nil) }

    it "LOAD-002 caps positive bias against the previous generated load without rewriting it" do
      previous = outline(date: today - 7, level: 1)
      described_class.new(plan, date: today - 7).call
      previous_snapshot = [ previous.reload.attributes, steps(previous) ]
      plan.update!(progression_state: { "intensity_bias" => 2 })
      workout = outline(level: 7)
      warnings = described_class.new(plan).call
      expect(workout.reload.estimated_tss).to be <= previous.estimated_tss * 1.08
      expect(workout.progression_level).to be < 7
      expect([ previous.reload.attributes, steps(previous) ]).to eq(previous_snapshot)
      expect(warnings).to be_empty
    end

    it "keeps manual load visible without using it to increase the next generated baseline" do
      previous = outline(date: today - 7, level: 1)
      described_class.new(plan, date: today - 7).call
      baseline_tss = previous.reload.estimated_tss
      2.times { Workouts::ManualEditor.new(previous).apply!(action: :longer) }
      workout = outline(level: 7)
      described_class.new(plan).call
      expect(workout.reload.estimated_tss).to be <= baseline_tss * 1.08
      expect(previous.reload.duration_minutes).to eq(120)
    end

    it "warns when fixed workouts and expanded availability make the cap infeasible" do
      previous = generated_workout(plan: plan, phase: phase, date: today - 7, level: 1, duration: 30)
      fixed = generated_workout(plan: plan, phase: phase, date: today + 1, level: 7, duration: 120)
      fixed_snapshot = [ fixed.attributes, steps(fixed) ]
      workout = outline(level: 7, duration: 120)
      warnings = described_class.new(plan).call
      expect(workout.reload.progression_level).to eq(1)
      expect(workout.estimated_tss + fixed.estimated_tss).to be > previous.estimated_tss * 1.08
      expect(warnings).to include(a_string_including("8% growth target"))
      expect(described_class.new(plan).call).to eq(warnings)
      expect([ fixed.reload.attributes, steps(fixed) ]).to eq(fixed_snapshot)
    end

    it "uses canonical fixed steps when a reference workout lacks stored metrics" do
      previous = generated_workout(plan: plan, phase: phase, date: today - 7, level: 3, duration: 90)
      previous.workout_steps.each do |step|
        attributes = { target_low_pct_ftp: 45, target_high_pct_ftp: 45 }
        attributes.merge!(end_target_low_pct_ftp: 45, end_target_high_pct_ftp: 45) if step.ramp?
        step.update!(attributes)
      end
      previous.update!(estimated_tss: nil)
      snapshot = [ previous.attributes, steps(previous) ]
      workout = outline(level: 3)
      expect(described_class.new(plan).call).to include(a_string_including("8% growth target"))
      expect(workout.reload.progression_level).to eq(1)
      expect([ previous.reload.attributes, steps(previous) ]).to eq(snapshot)
    end

    it "ignores a recovery week when finding the previous hard-week reference" do
      plan.update!(progression_state: { "intensity_bias" => 1 })
      # The cycle is immutable, so use a dedicated plan with alternating weeks.
      recovery_plan = create(:training_plan, starts_on: today - 28, ends_on: today + 83, hard_weeks_before_recovery: 1)
      recovery_phase = create(:plan_phase, training_plan: recovery_plan, starts_on: recovery_plan.starts_on, ends_on: recovery_plan.ends_on)
      previous = generated_workout(plan: recovery_plan, phase: recovery_phase, date: today - 14, level: 3, duration: 90)
      generated_workout(plan: recovery_plan, phase: recovery_phase, date: today - 7, subtype: :recovery, duration: 30)
      workout = create(
        :planned_workout,
        training_plan: recovery_plan,
        plan_phase: recovery_phase,
        scheduled_on: today,
        intent: :threshold,
        subtype: :threshold,
        progression_level: 3,
        duration_minutes: 90)
      described_class.new(recovery_plan).call
      expect(workout.reload.progression_level).to eq(3)
      expect(workout.estimated_tss).to be <= previous.estimated_tss * 1.08
    end

    it "does not bias or restructure overdue and completed records when FTP changes" do
      completed = create(:planned_workout, :completed, training_plan: plan, plan_phase: phase, scheduled_on: today - 2)
      overdue = outline(date: today - 1)
      snapshot = [ completed.attributes, steps(completed), completed.workout_feedback.attributes ]
      current = outline
      profile = create(:rider_profile, user: plan.user)
      plan.update!(progression_state: { "intensity_bias" => -1 })
      described_class.new(plan).call
      structure = steps(current)
      profile.update!(ftp_watts: 320)
      Planning::FtpRecalculator.new(profile: profile).call
      described_class.new(plan).call
      expect(steps(current)).to eq(structure)
      expect(overdue.reload).to be_outline
      expect([ completed.reload.attributes, steps(completed), completed.workout_feedback.attributes ]).to eq(snapshot)
    end
  end
end
