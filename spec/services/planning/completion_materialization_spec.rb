require "rails_helper"

RSpec.describe Planning::WorkoutBuilder, generated_workouts: true do
  let(:today) { Date.new(2026, 10, 5) }
  let(:plan) { create(:training_plan, starts_on: today - 28, ends_on: today + 55, progression_mode: :continuous, hard_weeks_before_recovery: nil) }
  let(:phase) { create(:plan_phase, training_plan: plan, starts_on: plan.starts_on, ends_on: plan.ends_on, kind: :build) }

  before { travel_to today }

  def outline(date: today - 7, **attributes)
    create(
      :planned_workout,
      training_plan: plan,
      plan_phase: phase,
      scheduled_on: date,
      subtype: :threshold,
      intent: :threshold,
      duration_minutes: 90,
      progression_level: 3,
      variation_key: "standard",
      **attributes)
  end

  def snapshot(workout)
    [ workout.reload.attributes, workout.workout_steps.reload.map(&:attributes) ]
  end

  it "FBK-003 uses saved prescription context and variation, accepted bias and current owner FTP only once" do
    create(:rider_profile, user: plan.user, ftp_watts: 280)
    plan.update!(progression_state: { "intensity_bias" => 2 })
    workout = outline(variation_key: "redistributed_recovery", generation_context: { "baseline_level" => 3, "maximum_level" => 4 })
    builder = described_class.new(plan)
    builder.build_for_completion!(workout)
    definition = Workouts::Generator.new(
      subtype: :threshold,
      duration_minutes: 90,
      progression_level: 4,
      variation_key: "redistributed_recovery",
      phase: :build,
      goal: plan.goal,
      discipline: plan.discipline).call
    expect(workout.workout_steps.map { |step| Workouts::StepDefinition.from(step).to_h }).to eq(definition.steps.map(&:to_h))
    expect(workout).to have_attributes(progression_level: 4, variation_key: "redistributed_recovery")
    expect(workout.generation_context).to include("baseline_level" => 3, "maximum_level" => 4, "generated_level" => 4)
    before = snapshot(workout)
    builder.build_for_completion!(workout)
    expect(snapshot(workout)).to eq(before)
  end

  it "LOAD-002 limits only the requested overdue workout against the preceding comparable week" do
    previous = generated_workout(plan: plan, phase: phase, date: today - 14, level: 1, duration: 90)
    workout = outline(progression_level: 7)
    other = outline(date: today - 6)
    current = outline(date: today)
    before = [ previous, other, current ].map { |item| snapshot(item) }
    described_class.new(plan).build_for_completion!(workout)
    expect(workout.reload.progression_level).to eq(1)
    expect([ previous, other, current ].map { |item| snapshot(item) }).to eq(before)
    expect(workout.duration_minutes).to eq(90)
  end

  it "FBK-003 saves an initial endurance profile and keeps it stable across repeat detail reads" do
    workout = outline(subtype: :endurance, intent: :endurance, progression_level: nil, variation_key: nil)
    described_class.new(plan).build_for_completion!(workout)
    expect(workout.variation_key).to be_in(%w[sustained alternating undulating])
    before = snapshot(workout)
    described_class.new(plan).build_for_completion!(workout)
    expect(snapshot(workout)).to eq(before)
  end

  it "USR-004 rejects a workout belonging to another plan before materialisation" do
    workout = outline
    other_plan = create(:training_plan, starts_on: plan.starts_on, ends_on: plan.ends_on)
    before = snapshot(workout)
    expect { described_class.new(other_plan).build_for_completion!(workout) }.to raise_error(ArgumentError)
    expect(snapshot(workout)).to eq(before)
  end

  it "FBK-001 rejects missed, completed and future outline sources without changes" do
    missed = outline(status: :missed)
    completed = create(:planned_workout, :completed, training_plan: plan, plan_phase: phase, scheduled_on: today - 6)
    future = outline(date: today + 1)
    [ missed, completed, future ].each do |workout|
      before = snapshot(workout)
      expect { described_class.new(plan).build_for_completion!(workout) }.to raise_error(ArgumentError)
      expect(snapshot(workout)).to eq(before)
    end
  end
end
