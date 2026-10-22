require "rails_helper"

RSpec.describe Planning::AvailabilityForWeek, type: :service do
  let(:monday) { Date.new(2026, 10, 5) }
  let(:plan) { create(:training_plan, starts_on: monday, ends_on: monday + 55, progression_mode: :continuous, hard_weeks_before_recovery: nil) }
  let!(:base) do
    create(:availability_template, training_plan: plan, effective_from: plan.starts_on).tap do |template|
      create(:availability_slot, availability_template: template, weekday: 2, duration_minutes: 60, intent: :intervals)
      create(:availability_slot, availability_template: template, weekday: 6, duration_minutes: 120, intent: :endurance)
    end
  end

  def durations(date)
    described_class.new(plan.reload, date: date).call.transform_values(&:duration_minutes)
  end

  it "returns the slot for each available weekday of the date's calendar week" do
    expect(durations(monday + 3)).to eq(2 => 60, 6 => 120)
  end

  it "prefers a one-week override over the base template only inside the override week" do
    override = create(:availability_template, training_plan: plan, effective_from: monday + 7, effective_until: monday + 13, source: :one_week_override)
    create(:availability_slot, availability_template: override, weekday: 4, duration_minutes: 45, intent: :recovery)

    expect(durations(monday + 7)).to eq(4 => 45)
    expect(durations(monday)).to eq(2 => 60, 6 => 120)
    expect(durations(monday + 14)).to eq(2 => 60, 6 => 120)
  end

  it "uses the template with the latest effective date once a change has been versioned" do
    base.update!(effective_until: monday + 13)
    later = create(:availability_template, training_plan: plan, effective_from: monday + 14, source: :from_date_change)
    create(:availability_slot, availability_template: later, weekday: 3, duration_minutes: 90, intent: :endurance)

    expect(durations(monday + 7)).to eq(2 => 60, 6 => 120)
    expect(durations(monday + 14)).to eq(3 => 90)
  end

  it "clamps days outside the plan to its first and last day" do
    expect(durations(monday - 7)).to eq(2 => 60, 6 => 120)
    expect(durations(plan.ends_on + 7)).to eq(2 => 60, 6 => 120)
  end

  it "leaves out weekdays with no slot, and returns nothing when no template applies" do
    base.update!(effective_until: monday + 6)

    expect(durations(monday + 3)).to eq(2 => 60, 6 => 120)
    expect(durations(monday + 10)).to eq({})
  end
end
