require "rails_helper"

RSpec.describe Planning::PlanCreator, type: :service do
  def configuration
    Planning::PlanConfiguration.new(goal: "increase_ftp", discipline: "road", starts_on: Date.new(2026, 9, 7), duration_mode: "preset", duration_months: 3, ftp_watts: 260, include_base: true, progression_mode: "hard_recovery_cycle", hard_weeks_before_recovery: 3, availability: { "1" => { enabled: "1", weekday: "1", duration_minutes: "60", intent: "intervals" }, "3" => { enabled: "1", weekday: "3", duration_minutes: "90", intent: "endurance" }, "6" => { enabled: "1", weekday: "6", duration_minutes: "60", intent: "intervals" } })
  end

  it "PLN-013 persists the same preview transactionally with only the 14-day horizon structured" do
    preview = Planning::PlanBuilder.new(configuration).preview
    plan = described_class.new(configuration).create!
    expect(plan).to be_active
    expect(plan.plan_phases.map { |phase| [ phase.kind, phase.starts_on, phase.ends_on ] }).to eq(preview.phases.map { |phase| [ phase.kind, phase.starts_on, phase.ends_on ] })
    expect(plan.planned_workouts.count).to eq(preview.prescriptions.count { |item| item.kind != "event" })
    expect(plan.planned_workouts.structured.pluck(:scheduled_on)).to all(be_between(Date.current, Date.current + 13))
    expect(plan.planned_workouts.structured).to all(satisfy { |workout| workout.workout_steps.sum(:duration_seconds) == workout.duration_minutes * 60 })
    expect(plan.planned_workouts.outline.where(kind: :workout).where("scheduled_on > ?", Date.current + 13)).to exist
    expect(plan.availability_templates.sole.availability_slots.count).to eq(3)
  end

  it "materialises a later outline idempotently when it enters the horizon" do
    plan = described_class.new(configuration).create!
    future = plan.planned_workouts.outline.where(kind: :workout).order(:scheduled_on).first
    Planning::HorizonMaterializer.new(plan, date: future.scheduled_on).call
    expect(future.reload).to be_structured
    expect(future.workout_steps).not_to be_empty
  end
end
