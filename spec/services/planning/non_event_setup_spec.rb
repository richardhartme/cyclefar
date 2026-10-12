require "rails_helper"

RSpec.describe "CYF-87 non-event setup compatibility", generated_workouts: true do
  let(:start) { Date.new(2026, 9, 7) }
  before { travel_to start }

  def configuration(goal = "increase_ftp", discipline = nil)
    Planning::PlanConfiguration.new(
      goal: goal,
      discipline: discipline,
      event_discipline: "invalid",
      event_distance_km: -1,
      starts_on: start,
      plan_length: "3",
      ftp_watts: 260,
      include_base: true,
      availability: { "2" => { enabled: "1", weekday: "2", duration_minutes: "60", intent: "intervals" },
                      "4" => { enabled: "1", weekday: "4", duration_minutes: "90", intent: "endurance" } })
  end

  %w[general_fitness increase_ftp improve_endurance improve_climbing].each do |goal|
    it "previews and confirms #{goal} with internal Road regardless of inactive input" do
      config = configuration(goal, "invalid")
      preview = Planning::PlanBuilder.new(config).preview
      plan = Planning::PlanCreator.new(config, user: create(:user)).create!
      expect(plan).to have_attributes(goal: goal, discipline: "road", ends_on: preview.ends_on)
      expect(plan.target_event).to be_nil
      expect(plan.planned_workouts.order(:scheduled_on).pluck(:scheduled_on, :subtype, :duration_minutes))
        .to eq(preview.prescriptions.map { |item| [ item.scheduled_on, item.subtype, item.duration_minutes ] })
    end
  end

  it "preserves a legacy non-Road plan and completed history through materialisation, availability and time off" do
    config = configuration
    preview = Planning::PlanBuilder.new(config).preview
    plan = create(
      :training_plan,
      goal: :increase_ftp,
      discipline: :gravel,
      starts_on: start,
      ends_on: preview.ends_on,
      include_base: true,
      progression_mode: :continuous,
      hard_weeks_before_recovery: nil)
    preview.phases.each do |phase|
      plan.plan_phases.create!(kind: phase.kind, starts_on: phase.starts_on, ends_on: phase.ends_on, position: phase.position)
    end
    template = plan.availability_templates.create!(effective_from: start, source: :initial)
    config.availability.each { |slot| template.availability_slots.create!(slot.to_h) }
    Planning::FuturePrescriber.new(plan: plan, slots: config.availability).replace!(start..plan.ends_on)
    completed = plan.planned_workouts.structured.order(:scheduled_on).first!
    Adaptations::CompletionRecorder.new(workout: completed, rpe: 8, completion_quality: :as_planned).call
    history = -> { [ completed.reload.attributes, completed.workout_steps.reload.map(&:attributes), completed.workout_feedback.reload.attributes ] }
    snapshot = history.call
    existing = Planning::ExistingPlanConfiguration.new(plan: plan, availability: config.availability)
    expect(existing.training_discipline).to eq("gravel")
    future = plan.planned_workouts.outline.order(:scheduled_on).first!
    Planning::WorkoutBuilder.new(plan, date: future.scheduled_on).call
    expect(future.reload).to be_structured
    Planning::AvailabilityChanger.new(
      plan: plan, slots: config.availability.map(&:to_h), effective_from: start + 14, scope: :from_date).apply!
    Planning::TimeOffPlanner.new(plan: plan).add!(starts_on: start + 30, ends_on: start + 32, reason: :holiday)
    expect(plan.reload.discipline).to eq("gravel")
    expect(history.call).to eq(snapshot)
  end
end
