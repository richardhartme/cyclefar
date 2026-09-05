require "rails_helper"

RSpec.describe Planning::TimeOffPlanner, type: :service do
  let(:plan) { create(:training_plan, :event, starts_on: Date.current - 14, ends_on: Date.current + 70) }
  let!(:phase) { create(:plan_phase, training_plan: plan, starts_on: plan.starts_on, ends_on: plan.ends_on) }
  let(:template) { create(:availability_template, training_plan: plan, effective_from: plan.starts_on) }
  let(:starts_on) { Date.current.next_occurring(:tuesday) }
  let(:ends_on) { starts_on + 2 }

  before do
    create(:availability_slot, availability_template: template, weekday: 2, duration_minutes: 60, intent: :intervals)
    create(:availability_slot, availability_template: template, weekday: 4, duration_minutes: 60, intent: :intervals)
    create(:availability_slot, availability_template: template, weekday: 6, duration_minutes: 90, intent: :intervals)
  end

  it "removes planned workouts during illness and builds deterministic short and long re-entry stages" do
    in_break = create(:planned_workout, training_plan: plan, plan_phase: phase, scheduled_on: starts_on)
    completed = create(:planned_workout, :completed, training_plan: plan, plan_phase: phase, scheduled_on: starts_on + 1)

    period = described_class.new(plan: plan).add!(starts_on: starts_on, ends_on: ends_on, reason: :illness, return_ramp_days: 14)

    expect { in_break.reload }.to raise_error(ActiveRecord::RecordNotFound)
    expect(completed.reload).to be_completed
    expect(plan.planned_workouts.planned.where(scheduled_on: starts_on..ends_on)).to be_empty
    first_return = plan.planned_workouts.find_by!(scheduled_on: ends_on + 2)
    expect(first_return.subtype).to be_in(%w[recovery endurance])
    expect(first_return.duration_minutes).to be_between(30, 63)
    later_return = plan.planned_workouts.where(scheduled_on: (ends_on + 3)..(ends_on + 14)).order(:scheduled_on).last
    expect(later_return).to be_present
    expect(later_return.duration_minutes).to be_between(30, 90)
    expect(period.return_ramp_days).to eq(14)
    expect(plan.ends_on).to eq(Date.current + 70)
  end

  it "resumes holiday progression from the pre-break level and restores prescriptions when removed" do
    create(:planned_workout, training_plan: plan, plan_phase: phase, scheduled_on: starts_on - 7, subtype: :threshold, intent: :intervals, progression_level: 3)

    period = described_class.new(plan: plan).add!(starts_on: starts_on, ends_on: ends_on, reason: :holiday)
    resumed = plan.planned_workouts.where("scheduled_on > ?", ends_on).where.not(progression_level: nil).order(:scheduled_on).first!
    expect(resumed.progression_level).to be <= 3

    described_class.new(plan: plan).remove!(period)
    expect(plan.planned_workouts.planned.where(scheduled_on: starts_on..ends_on)).not_to be_empty
    expect(plan.ends_on).to eq(Date.current + 70)
  end

  it "collapses a short return ramp without scheduling more than one workout per date" do
    period = described_class.new(plan: plan).add!(starts_on: starts_on, ends_on: ends_on, reason: :recovery, return_ramp_days: 2)
    return_date = ends_on + 2

    expect(period.return_ramp_days).to eq(2)
    expect(plan.planned_workouts.where(scheduled_on: return_date).count).to eq(1)
    expect(plan.planned_workouts.find_by!(scheduled_on: return_date).duration_minutes).to be_between(30, 90)
  end

  it "keeps the target event and phase records while a taper-day opener is removed for time off" do
    event = create(:target_event, training_plan: plan, event_on: plan.ends_on)
    opener = create(:planned_workout, training_plan: plan, plan_phase: phase, kind: :opener, intent: :intervals, subtype: :endurance,
      duration_minutes: 30, scheduled_on: plan.ends_on - 1, name: "Event Opener", purpose: "Activation")

    described_class.new(plan: plan).add!(starts_on: plan.ends_on - 1, ends_on: plan.ends_on - 1, reason: :other)

    expect { opener.reload }.to raise_error(ActiveRecord::RecordNotFound)
    expect(plan.target_event).to eq(event)
    expect(plan.plan_phases).to contain_exactly(phase)
    expect(plan.ends_on).to eq(event.event_on)
  end
end
