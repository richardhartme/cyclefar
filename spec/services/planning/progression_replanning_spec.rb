require "rails_helper"

RSpec.describe "FBK-002 progression during explicit replanning", generated_workouts: true do
  let(:today) { Date.new(2026, 10, 5) }
  let(:plan) { create(:training_plan, starts_on: today - 28, ends_on: today + 83, progression_mode: :continuous, hard_weeks_before_recovery: nil) }
  let(:phase) { create(:plan_phase, training_plan: plan, starts_on: plan.starts_on, ends_on: plan.ends_on, kind: :build) }
  let(:slots) { [ { weekday: 1, duration_minutes: 90, intent: "threshold" } ] }

  before { travel_to today }

  [ -1, 1 ].each do |bias|
    it "OFF-001 resumes from the reached level with bias #{bias} without applying it twice" do
      previous = create(
        :planned_workout,
        training_plan: plan,
        plan_phase: phase,
        scheduled_on: today - 7,
        intent: :threshold,
        subtype: :threshold,
        progression_level: 3,
        duration_minutes: 90)
      plan.update!(progression_state: { "intensity_bias" => bias })
      Planning::WorkoutBuilder.new(plan, date: today - 7).call
      reached = previous.reload.progression_level
      create(:time_off_period, training_plan: plan, starts_on: today - 3, ends_on: today - 1)
      prescriber = Planning::FuturePrescriber.new(plan: plan, slots: slots)
      prescriber.replace!(today..today + 13)
      returned = plan.planned_workouts.find_by!(scheduled_on: today)
      expect(returned.progression_level).to be <= reached
      expected = Training::V1::Progression.level(
        baseline: returned.generation_context.fetch("baseline_level"), bias: bias, maximum: reached)
      expect(returned.progression_level).to eq(expected)
      canonical = returned.workout_steps.map { |step| Workouts::StepDefinition.from(step).to_h }
      prescriber.replace!(today..today + 13)
      returned = plan.planned_workouts.find_by!(scheduled_on: today)
      expect(returned.progression_level).to eq(expected)
      expect(returned.workout_steps.map { |step| Workouts::StepDefinition.from(step).to_h }).to eq(canonical)
      expect(plan.reload.progression_state).to eq("intensity_bias" => bias)
    end
  end

  it "OFF-001 keeps positive bias within every illness return-stage ceiling" do
    plan.update!(progression_state: { "intensity_bias" => 2 })
    generated_workout(plan: plan, phase: phase, date: today - 7, level: 4, duration: 90)
    create(:time_off_period, training_plan: plan, starts_on: today - 3, ends_on: today - 1, reason: :illness, return_ramp_days: 14)
    daily = (1..7).map { |weekday| { weekday: weekday, duration_minutes: 90, intent: "threshold" } }
    Planning::FuturePrescriber.new(plan: plan, slots: daily).replace!(today..today + 13)
    workouts = plan.planned_workouts.where(scheduled_on: today..today + 13).order(:scheduled_on)
    expect(workouts.first.subtype).to eq("recovery")
    expect(workouts[4].subtype).to eq("endurance")
    expect(workouts[7]).to have_attributes(subtype: "tempo", progression_level: 1)
    workouts.select { |workout| workout.progression_level }.each do |workout|
      expect(workout.progression_level).to be <= workout.generation_context.fetch("maximum_level")
    end
  end

  it "SCH-001 preserves accepted bias across availability changes while future outlines remain unbiased" do
    plan.update!(progression_state: { "intensity_bias" => -1 })
    phase
    Planning::AvailabilityChanger.new(plan: plan, slots: slots, effective_from: today, scope: :from_date).apply!
    current = plan.planned_workouts.find_by!(scheduled_on: today)
    baseline = current.generation_context.fetch("baseline_level")
    expect(current.progression_level).to eq([ baseline - 1, 1 ].max)
    future = plan.planned_workouts.workout.outline.where("scheduled_on > ?", today + 13).order(:scheduled_on).first!
    forecast_level = future.progression_level
    Planning::WorkoutBuilder.new(plan, date: future.scheduled_on).call
    expect(future.reload.progression_level).to be <= [ forecast_level - 1, 1 ].max
    expect(plan.reload.progression_state).to eq("intensity_bias" => -1)
  end

  it "keeps the taper ceiling even with positive accepted bias" do
    event_plan = create(
      :training_plan,
      :event,
      starts_on: today - 28,
      ends_on: today + 13,
      progression_state: { "intensity_bias" => 2 })
    create(:plan_phase, training_plan: event_plan, starts_on: event_plan.starts_on, ends_on: today - 1)
    taper = create(:plan_phase, training_plan: event_plan, kind: :taper, starts_on: today, ends_on: today + 13, position: 2)
    workout = create(
      :planned_workout,
      training_plan: event_plan,
      plan_phase: taper,
      scheduled_on: today,
      intent: :threshold,
      subtype: :threshold,
      progression_level: 2,
      duration_minutes: 90)
    Planning::WorkoutBuilder.new(event_plan).call
    expect(workout.reload.progression_level).to eq(2)
  end
end
