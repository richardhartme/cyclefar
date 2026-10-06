require "rails_helper"

RSpec.describe "CYF-11 persisted phase treatment", generated_workouts: true do
  let(:start) { Date.new(2026, 9, 7) }
  let(:event) { Date.new(2026, 12, 6) }
  let(:config) do
    Planning::PlanConfiguration.new(
      goal: "event",
      discipline: "road",
      starts_on: start,
      event_name: "Autumn Classic",
      event_on: event,
      event_expected_duration_minutes: 360,
      ftp_watts: 260,
      include_base: true,
      progression_mode: "hard_recovery_cycle",
      hard_weeks_before_recovery: 3,
      availability: { "2" => { enabled: "1", weekday: "2", duration_minutes: "90", intent: "threshold" },
              "4" => { enabled: "1", weekday: "4", duration_minutes: "90", intent: "endurance" },
              "6" => { enabled: "1", weekday: "6", duration_minutes: "60", intent: "vo2_max" },
              "7" => { enabled: "1", weekday: "7", duration_minutes: "120", intent: "endurance" } })
  end

  before { travel_to start }

  it "uses identical aligned recovery weeks in preview, calendar, load references and regeneration" do
    preview = Planning::PlanBuilder.new(config).preview
    plan = Planning::PlanCreator.new(config, user: create(:user)).create!
    calendar = Planning::CalendarPresenter.new(plan).weeks
    expect(calendar.select(&:recovery_week).map(&:starts_on)).to eq(preview.weeks.select(&:recovery_week).map(&:starts_on))
    context = Planning::LoadContext.new(plan)
    preview.weeks.select(&:recovery_week).each do |week|
      workouts = plan.planned_workouts.where(scheduled_on: week.starts_on..week.ends_on).to_a
      expect(context.comparable_week?(week.starts_on, workouts)).to be(false)
      expect(workouts.map(&:subtype)).to all(be_in(%w[endurance recovery]))
    end
    slots = plan.availability_templates.sole.availability_slots.map { |slot| Planning::Availability.new(weekday: slot.weekday, duration_minutes: slot.duration_minutes, intent: slot.intent) }
    config_again = Planning::ExistingPlanConfiguration.new(plan: plan, availability: slots)
    expect(Planning::PlanBuilder.new(config_again).preview.weeks.map(&:recovery_week)).to eq(preview.weeks.map(&:recovery_week))
  end

  it "materialises saved taper structures at current FTP without positive bias escalating hard work or rewriting completed history" do
    user = create(:user)
    create(:rider_profile, user: user, ftp_watts: 285)
    preview = Planning::PlanBuilder.new(config).preview
    plan = Planning::PlanCreator.new(config, user: user).create!
    completed = plan.planned_workouts.structured.workout.first!
    Adaptations::CompletionRecorder.new(workout: completed, rpe: 8, completion_quality: :as_planned).call
    snapshot = [ completed.reload.attributes, completed.workout_steps.map(&:attributes), completed.workout_feedback.attributes ]
    plan.update!(progression_state: { "intensity_bias" => 2 })
    taper = preview.phases.last
    Planning::WorkoutBuilder.new(plan, date: taper.starts_on).call
    preview.prescriptions.select { |item| item.phase == "taper" && item.intensity? }.each do |item|
      workout = plan.planned_workouts.find_by!(scheduled_on: item.scheduled_on)
      expect(workout).to be_structured
      expect(workout.workout_steps.map { |step| Workouts::StepDefinition.from(step).to_h }).to eq(item.definition.steps.map(&:to_h))
      expect(workout.generation_context.fetch("load_adjustments")).to eq(item.definition.load_adjustments)
      expect(workout.estimated_tss).to be_within(0.001).of(item.estimated_tss)
    end
    expect([ completed.reload.attributes, completed.workout_steps.reload.map(&:attributes), completed.workout_feedback.reload.attributes ]).to eq(snapshot)
  end

  it "CYF-77 replans illness return and taper with executable training prescriptions instead of FTP tests" do
    plan = Planning::PlanCreator.new(config, user: create(:user)).create!
    break_date = start + 36
    period = Planning::TimeOffPlanner.new(plan: plan).add!(
      starts_on: break_date - 1,
      ends_on: break_date,
      reason: :illness,
      return_ramp_days: 14)
    slots = plan.availability_templates.sole.availability_slots.map { |slot| Planning::Availability.new(weekday: slot.weekday, duration_minutes: slot.duration_minutes, intent: slot.intent) }
    existing = Planning::ExistingPlanConfiguration.new(plan: plan, availability: slots)
    preview = Planning::PlanBuilder.new(existing).preview
    expect(preview.prescriptions.map(&:kind).uniq).to match_array(%w[workout opener event])
    expect(plan.planned_workouts.pluck(:kind).uniq).to match_array(%w[workout opener])
    expect(plan.planned_workouts.where(scheduled_on: period.starts_on..period.ends_on)).not_to exist
    expect(plan.planned_workouts.find_by!(scheduled_on: break_date + 7)).to have_attributes(kind: "workout", generation_context: include("return_ramp_stage"))
    preview.prescriptions.select { |item| item.phase == "taper" && item.intensity? }.each do |item|
      workout = plan.planned_workouts.find_by!(scheduled_on: item.scheduled_on)
      expect(workout.generation_context.fetch("load_adjustments")).to eq(item.definition.load_adjustments)
      expect(workout.progression_level).to be <= item.progression_level
    end
  end
end
