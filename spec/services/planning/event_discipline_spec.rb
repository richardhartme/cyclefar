require "rails_helper"

RSpec.describe "CYF-85 event discipline consistency", generated_workouts: true do
  let(:start) { Date.new(2026, 9, 7) }
  let(:user) { create(:user) }
  let(:configuration) do
    Planning::PlanConfiguration.new(
      goal: "event",
      discipline: "road",
      event_discipline: "mtb",
      starts_on: start,
      event_on: Date.new(2026, 12, 6),
      event_name: "Trail race",
      ftp_watts: 260,
      include_base: false,
      progression_mode: "continuous",
      availability: { "2" => { enabled: "1", weekday: "2", duration_minutes: "90", intent: "intervals" },
                            "4" => { enabled: "1", weekday: "4", duration_minutes: "90", intent: "threshold" } })
  end

  before { travel_to start }

  def history(workout)
    [ workout.reload.attributes, workout.workout_steps.reload.map(&:attributes), workout.workout_feedback.reload.attributes ]
  end

  it "uses the preview discipline for creation, horizon materialisation and explicit replanning without rewriting completed history" do
    preview = Planning::PlanBuilder.new(configuration).preview
    plan = Planning::PlanCreator.new(configuration, user: user).create!
    expect(plan.discipline).to eq("mtb")
    expect(plan.target_event.discipline).to eq("mtb")
    expect(plan.planned_workouts.order(:scheduled_on).pluck(:scheduled_on, :subtype, :duration_minutes))
      .to eq(preview.prescriptions.select(&:executable?).map { |item| [ item.scheduled_on, item.subtype, item.duration_minutes ] })

    completed = plan.planned_workouts.structured.order(:scheduled_on).first!
    Adaptations::CompletionRecorder.new(workout: completed, rpe: 8, completion_quality: :as_planned).call
    snapshot = history(completed)
    future = plan.planned_workouts.outline.where(intent: :intervals).order(:scheduled_on).first!
    expected = preview.prescriptions.find { |item| item.scheduled_on == future.scheduled_on }
    Planning::WorkoutBuilder.new(plan, date: future.scheduled_on).call
    expect(future.reload).to be_structured
    expect(future.subtype).to eq(expected.subtype)
    expect(future.workout_steps.map { |step| Workouts::StepDefinition.from(step).to_h }).to eq(expected.definition.steps.map(&:to_h))

    slots = configuration.availability
    existing = Planning::ExistingPlanConfiguration.new(plan: plan, availability: slots)
    expect(existing.training_discipline).to eq("mtb")
    expect(Planning::PlanBuilder.new(existing).preview.prescriptions).to eq(preview.prescriptions)
    Planning::FuturePrescriber.new(plan: plan, slots: slots).replace!(plan.starts_on..plan.ends_on)
    expect(plan.planned_workouts.order(:scheduled_on).pluck(:scheduled_on, :subtype, :duration_minutes))
      .to eq(preview.prescriptions.select(&:executable?).map { |item| [ item.scheduled_on, item.subtype, item.duration_minutes ] })
    expect(history(completed)).to eq(snapshot)
  end

  it "preserves a legacy plan's training discipline when its event label differs" do
    legacy = create(
      :training_plan,
      :event,
      user: user,
      discipline: :mtb,
      starts_on: start,
      ends_on: configuration.ends_on,
      include_base: false,
      progression_mode: :continuous,
      hard_weeks_before_recovery: nil)
    create(:target_event, training_plan: legacy, discipline: :road)
    Planning::PlanBuilder.new(configuration).preview.phases.each do |phase|
      legacy.plan_phases.create!(kind: phase.kind, starts_on: phase.starts_on, ends_on: phase.ends_on, position: phase.position)
    end
    Planning::FuturePrescriber.new(plan: legacy, slots: configuration.availability).replace!(legacy.starts_on..legacy.ends_on)
    completed = legacy.planned_workouts.structured.order(:scheduled_on).first!
    Adaptations::CompletionRecorder.new(workout: completed, rpe: 8, completion_quality: :as_planned).call
    snapshot = history(completed)
    existing = Planning::ExistingPlanConfiguration.new(plan: legacy, availability: configuration.availability)
    expect(existing).to have_attributes(training_discipline: "mtb", event_discipline: "road")
    baseline = legacy.planned_workouts.order(:scheduled_on).pluck(:scheduled_on, :subtype, :duration_minutes)
    Planning::FuturePrescriber.new(plan: legacy, slots: configuration.availability).replace!(legacy.starts_on..legacy.ends_on)
    expect(legacy.reload.discipline).to eq("mtb")
    expect(legacy.target_event.discipline).to eq("road")
    expect(legacy.planned_workouts.order(:scheduled_on).pluck(:scheduled_on, :subtype, :duration_minutes)).to eq(baseline)
    expect(history(completed)).to eq(snapshot)
  end
end
