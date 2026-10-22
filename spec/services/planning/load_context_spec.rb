require "rails_helper"

RSpec.describe Planning::LoadContext, type: :service do
  let(:monday) { Date.new(2026, 10, 5) }
  let(:plan) { create(:training_plan, :event, starts_on: monday - 28, ends_on: monday + 55, progression_mode: :continuous, hard_weeks_before_recovery: nil) }
  let!(:base) { create(:plan_phase, training_plan: plan, starts_on: plan.starts_on, ends_on: monday + 37) }
  let!(:taper) { create(:plan_phase, training_plan: plan, starts_on: monday + 38, ends_on: plan.ends_on, kind: :taper, position: 2) }

  def comparable?(week_offset)
    described_class.new(plan.reload).comparable_week?(monday + week_offset, [])
  end

  describe "#comparable_week?" do
    it "accepts an ordinary week inside the plan" do
      expect(comparable?(0)).to be(true)
      expect(comparable?(-28)).to be(true)
    end

    it "rejects weeks that start before the plan or end after it" do
      expect(comparable?(-35)).to be(false)
      expect(comparable?(56)).to be(false)
    end

    it "rejects a week that overlaps any day of the taper" do
      expect(comparable?(28)).to be(true)
      expect(comparable?(35)).to be(false)
    end

    it "rejects a week that overlaps a break at either end" do
      create(:time_off_period, training_plan: plan, starts_on: monday + 13, ends_on: monday + 15, reason: :holiday)

      expect([ 0, 7, 14, 21 ].map { |offset| comparable?(offset) }).to eq([ true, false, false, true ])
    end

    it "rejects weeks that the return ramp reaches and accepts the first week it misses" do
      create(:time_off_period, training_plan: plan, starts_on: monday + 7, ends_on: monday + 8, reason: :illness, return_ramp_days: 12)

      expect([ 7, 14, 21 ].map { |offset| comparable?(offset) }).to eq([ false, false, true ])
    end

    it "treats a ramp ending exactly on a Monday as reaching that week" do
      create(:time_off_period, training_plan: plan, starts_on: monday + 7, ends_on: monday + 8, reason: :recovery, return_ramp_days: 13)
      create(:time_off_period, training_plan: plan, starts_on: monday + 22, ends_on: monday + 23, reason: :recovery, return_ramp_days: 3)

      expect(comparable?(14)).to be(false)
      expect(comparable?(21)).to be(false)
      expect(comparable?(28)).to be(true)
    end

    it "does not extend a holiday, which has no ramp, beyond its last day" do
      create(:time_off_period, training_plan: plan, starts_on: monday + 15, ends_on: monday + 20, reason: :holiday)

      expect(comparable?(14)).to be(false)
      expect(comparable?(21)).to be(true)
    end
  end

  describe "#maximum_level" do
    before { create(:time_off_period, training_plan: plan, starts_on: monday + 7, ends_on: monday + 8, reason: :illness, return_ramp_days: 7) }

    def maximum_for(offset)
      workout = build(:planned_workout, training_plan: plan, plan_phase: base, scheduled_on: monday + offset, progression_level: 3)
      described_class.new(plan.reload).maximum_level(workout)
    end

    it "holds a workout at its level for exactly the days of the return ramp" do
      expect([ 8, 9, 15, 16 ].map { |offset| maximum_for(offset) }).to eq([ nil, 3, 3, nil ])
    end
  end
end
