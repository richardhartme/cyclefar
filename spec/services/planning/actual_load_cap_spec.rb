require "rails_helper"

RSpec.describe "LOAD-002 actual generated load", generated_workouts: true do
  let(:today) { Date.new(2026, 10, 5) }
  let(:plan) { create(:training_plan, starts_on: today - 21, ends_on: today + 62, progression_mode: :continuous, hard_weeks_before_recovery: nil) }
  let(:phase) { create(:plan_phase, training_plan: plan, starts_on: plan.starts_on, ends_on: plan.ends_on, kind: :build) }

  before { travel_to today }

  def snapshot(workout)
    [ workout.reload.attributes, workout.workout_steps.reload.map(&:attributes) ]
  end

  %w[alternating undulating].each do |profile|
    it "rechecks randomly chosen #{profile} endurance load rather than relying on the sustained forecast" do
      reference = generated_workout(plan: plan, phase: phase, date: today - 7, subtype: :endurance, duration: 60, variation: "alternating")
      fixed = snapshot(reference)
      forecast = Workouts::Generator.new(subtype: :endurance, duration_minutes: 65).call
      forecast_tss = Metrics::WorkoutCalculator.new(steps: forecast.steps, ftp_watts: 260).call.estimated_tss
      limit = reference.estimated_tss.to_f * 1.08
      workout = create(
        :planned_workout,
        training_plan: plan,
        plan_phase: phase,
        scheduled_on: today,
        duration_minutes: 65,
        estimated_tss: forecast_tss)
      allow(Workouts::Variations).to receive(:for_generation).with("endurance", current_key: nil).and_return(profile)
      expect(forecast_tss).to be < limit
      actual = Workouts::Generator.new(subtype: :endurance, duration_minutes: 65, variation_key: profile).call
      expect(Metrics::WorkoutCalculator.new(steps: actual.steps, ftp_watts: 260).call.estimated_tss).to be > limit

      expect(Planning::WorkoutBuilder.new(plan).call).to be_empty
      expect(workout.reload).to have_attributes(variation_key: profile, duration_minutes: 65)
      expect(workout.estimated_tss.to_f).to be <= limit
      expect(workout.generation_context.fetch("load_adjustments")).to eq("lower_targets" => true)
      saved = snapshot(workout)
      Planning::WorkoutBuilder.new(plan).call
      expect(snapshot(workout)).to eq(saved)
      expect(snapshot(reference)).to eq(fixed)
      expect(Workouts::Variations).to have_received(:for_generation).once
    end
  end

  %w[threshold intervals].each do |intent|
    it "shows and accepts the same fully load-limited #{intent} adaptation, including its canonical steps" do
      reference = generated_workout(plan: plan, phase: phase, date: today - 7, level: 1, duration: 65)
      target = generated_workout(plan: plan, phase: phase, date: today + 1, level: 1, duration: 90)
      target.update!(intent: intent)
      completed = create(:planned_workout, :completed, training_plan: plan, plan_phase: phase, scheduled_on: today - 14)
      history = snapshot(completed)
      fixed = snapshot(reference)
      proposal = create(
        :adaptation_proposal,
        :fresh,
        training_plan: plan,
        payload: { "changes" => [ { "planned_workout_id" => target.id, "progression_level" => 2 } ] })
      comparison = Adaptations::ProposalComparison.new(proposal).call.changes.sole.preview
      expect(comparison.metrics.estimated_tss).to be <= reference.estimated_tss.to_f * 1.08
      expect(comparison.definition.load_adjustments).to include("lower_targets" => true)
      if intent == "threshold"
        expect(comparison.definition.subtype).to eq("threshold")
        expect(comparison.definition.load_adjustments).to include("easy_filler" => true)
      else
        expect(comparison.definition.subtype).to eq("sweet_spot")
      end
      Adaptations::ProposalApplier.new(proposal).accept!
      expect(target.reload.duration_minutes).to eq(90)
      expect(target.subtype).to eq(comparison.definition.subtype)
      expect(target.workout_steps.reload.map { |step| Workouts::StepDefinition.from(step) }).to eq(comparison.definition.steps)
      expect(target.estimated_tss.to_f).to be_within(0.001).of(comparison.metrics.estimated_tss)
      expect(target.generation_context.fetch("load_adjustments")).to eq(comparison.definition.load_adjustments)
      expect(snapshot(reference)).to eq(fixed)
      expect(snapshot(completed)).to eq(history)
      expect(Planning::WeeklyLoadReview.new(plan).warnings).to be_empty
    end
  end

  it "warns only after all valid choices are exhausted when availability expands beyond a feasible cap" do
    reference = generated_workout(plan: plan, phase: phase, date: today - 7, duration: 30, level: 1)
    workout = create(
      :planned_workout,
      training_plan: plan,
      plan_phase: phase,
      scheduled_on: today,
      subtype: :threshold,
      intent: :threshold,
      duration_minutes: 180,
      progression_level: 7)
    warnings = Planning::WorkoutBuilder.new(plan).call
    expect(workout.reload.duration_minutes).to eq(180)
    expect(workout.generation_context.fetch("load_adjustments")).to eq("lower_targets" => true, "easy_filler" => true)
    expect(workout.estimated_tss).to be > reference.estimated_tss * 1.08
    expect(warnings).to eq([ Planning::WeeklyLoadCap.warning(today) ])
    expect(Planning::WeeklyLoadReview.new(plan).warnings).to eq(warnings)
  end

  %w[holiday illness].each do |exclusion|
    it "uses the last comparable hard week across a #{exclusion} week" do
      reference = generated_workout(plan: plan, phase: phase, date: today - 21, level: 3, duration: 90)
      generated_workout(plan: plan, phase: phase, date: today - 14, subtype: :recovery, duration: 30)
      generated_workout(plan: plan, phase: phase, date: today - 1, subtype: :recovery, duration: 30)
      case exclusion
      when "holiday"
        create(:time_off_period, training_plan: plan, starts_on: today - 13, ends_on: today - 4, reason: :holiday)
      when "illness"
        create(:time_off_period, training_plan: plan, starts_on: today - 8, ends_on: today - 8, reason: :illness, return_ramp_days: 7)
      end
      workout = create(
        :planned_workout,
        training_plan: plan,
        plan_phase: phase,
        scheduled_on: today,
        subtype: :threshold,
        intent: :threshold,
        duration_minutes: 90,
        progression_level: 3)
      expect(Planning::WorkoutBuilder.new(plan).call).to be_empty
      expect(workout.reload.progression_level).to eq(3)
      review = Planning::WeeklyLoadReview.new(plan).call.find { |week| week.starts_on == today }
      expect(review.limit).to be_within(0.001).of(reference.estimated_tss.to_f * 1.08)
    end
  end

  it "does not use a partial first week as a hard-week baseline" do
    partial_plan = create(:training_plan, starts_on: today - 5, ends_on: today + 62, progression_mode: :continuous, hard_weeks_before_recovery: nil)
    partial_phase = create(:plan_phase, training_plan: partial_plan, starts_on: partial_plan.starts_on, ends_on: partial_plan.ends_on)
    generated_workout(plan: partial_plan, phase: partial_phase, date: today - 5, subtype: :recovery, duration: 30)
    workout = create(
      :planned_workout,
      training_plan: partial_plan,
      plan_phase: partial_phase,
      scheduled_on: today,
      subtype: :threshold,
      intent: :threshold,
      duration_minutes: 90,
      progression_level: 3)
    expect(Planning::WorkoutBuilder.new(partial_plan).call).to be_empty
    expect(workout.reload.progression_level).to eq(3)
    expect(Planning::WeeklyLoadReview.new(partial_plan).call.last.limit).to be_nil
  end

  it "excludes a taper week from the growth cap while retaining its separate level ceiling" do
    taper_plan = create(:training_plan, :event, starts_on: today - 21, ends_on: today + 6, progression_mode: :continuous, hard_weeks_before_recovery: nil)
    build = create(:plan_phase, training_plan: taper_plan, kind: :build, starts_on: taper_plan.starts_on, ends_on: today - 1)
    taper = create(:plan_phase, training_plan: taper_plan, kind: :taper, starts_on: today, ends_on: taper_plan.ends_on, position: 2)
    generated_workout(plan: taper_plan, phase: build, date: today - 7, subtype: :recovery, duration: 30)
    workout = create(
      :planned_workout,
      training_plan: taper_plan,
      plan_phase: taper,
      scheduled_on: today,
      subtype: :threshold,
      intent: :threshold,
      duration_minutes: 90,
      progression_level: 2)
    expect(Planning::WorkoutBuilder.new(taper_plan).call).to be_empty
    expect(workout.reload.progression_level).to eq(2)
    expect(Planning::WeeklyLoadReview.new(taper_plan).call.last.limit).to be_nil
  end

  it "retains preview reduction choices when an outline is persisted and later materialised" do
    config = Planning::PlanConfiguration.new(
      goal: "increase_ftp",
      discipline: "road",
      starts_on: today + 7,
      duration_mode: "custom",
      custom_duration_weeks: 12,
      ftp_watts: 260,
      include_base: true,
      progression_mode: "continuous",
      availability: { "1" => { enabled: "1", weekday: "1", duration_minutes: "90", intent: "intervals" } })
    preview = Planning::PlanBuilder.new(config).preview
    limited = preview.prescriptions.find { |item| !item.definition&.load_adjustments.to_h.empty? }
    expect(limited).to be_present
    expect(preview.warnings).to be_empty
    created = Planning::PlanCreator.new(config, user: create(:user)).create!
    workout = created.planned_workouts.find_by!(scheduled_on: limited.scheduled_on)
    expect(workout).to be_outline
    expect(workout.generation_context.fetch("load_adjustments")).to eq(limited.definition.load_adjustments)
    Planning::WorkoutBuilder.new(created, date: today + 1).call
    expect(workout.reload).to be_structured
    expect(workout.workout_steps.reload.map { |step| Workouts::StepDefinition.from(step) }).to eq(limited.definition.steps)
  end

  it "retains saved load reductions when a short move materialises an outline" do
    adjustments = { "lower_targets" => true, "easy_filler" => true }
    workout = create(
      :planned_workout,
      training_plan: plan,
      plan_phase: phase,
      scheduled_on: today + 14,
      subtype: :threshold,
      intent: :threshold,
      duration_minutes: 90,
      progression_level: 1,
      generation_context: { "maximum_level" => 1, "load_adjustments" => adjustments })
    expected = Workouts::Generator.new(
      subtype: :threshold,
      duration_minutes: 90,
      phase: :build,
      load_adjustments: adjustments).call
    Workouts::Mover.new(workout).move_to!(destination: today + 13)
    expect(workout.reload).to be_structured
    expect(workout.workout_steps.reload.map { |step| Workouts::StepDefinition.from(step) }).to eq(expected.steps)
    expect(workout.generation_context.fetch("load_adjustments")).to eq(adjustments)
  end
end
