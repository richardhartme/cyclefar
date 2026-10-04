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
    context = Planning::V1::LoadContext.new(plan)
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

  it "excludes time off and return ramps before ranking FTP slots, preserving a normal re-entry prescription" do
    plan = Planning::PlanCreator.new(config, user: create(:user)).create!
    assessment = plan.planned_workouts.ftp_test.order(:scheduled_on).first!
    period = Planning::TimeOffPlanner.new(plan: plan).add!(
      starts_on: assessment.scheduled_on - 1,
      ends_on: assessment.scheduled_on,
      reason: :illness,
      return_ramp_days: 14)
    slots = plan.availability_templates.sole.availability_slots.map { |slot| Planning::Availability.new(weekday: slot.weekday, duration_minutes: slot.duration_minutes, intent: slot.intent) }
    existing = Planning::ExistingPlanConfiguration.new(plan: plan, availability: slots)
    preview = Planning::PlanBuilder.new(existing).preview
    expect(preview.ftp_test_dates).not_to include(be_between(period.starts_on, period.ends_on + 14))
    expect(plan.planned_workouts.ftp_test.pluck(:scheduled_on)).not_to include(be_between(period.starts_on, period.ends_on + 14))
    expect(preview.prescriptions.find { |item| item.scheduled_on == assessment.scheduled_on + 7 }.kind).to eq("workout")
    tapered = preview.prescriptions.select { |item| item.phase == "taper" && item.intensity? }
    tapered.each do |item|
      workout = plan.planned_workouts.find_by!(scheduled_on: item.scheduled_on)
      expect(workout.generation_context.fetch("load_adjustments")).to eq(item.definition.load_adjustments)
      expect(workout.progression_level).to be <= item.progression_level
    end
  end
end
