require "engine_helper"
require_relative "../../app/services/planning/time_off_timeline"

RSpec.describe Planning::TimeOffTimeline do
  let(:period_class) { Struct.new(:id, :starts_on, :ends_on, :return_ramp_days) }
  let(:monday) { Date.new(2026, 10, 5) }
  let(:holiday) { period_class.new(1, monday + 7, monday + 9, nil) }
  let(:illness) { period_class.new(2, monday + 21, monday + 23, 7) }
  let(:timeline) { described_class.new([ illness, holiday ]) }

  describe "#break_on and #blocked?" do
    it "finds the period covering a date, inclusive at both ends" do
      expect([ 6, 7, 9, 10 ].map { |day| timeline.break_on(monday + day) }).to eq([ nil, holiday, holiday, nil ])
    end

    it "blocks the break itself and every day of a return ramp, but not the days around them" do
      blocked = (0..32).select { |day| timeline.blocked?(monday + day) }

      expect(blocked).to eq((7..9).to_a + (21..30).to_a)
    end
  end

  describe "#ramp_period_for" do
    it "returns the period whose ramp covers the date, from the day after the break to its last ramp day" do
      expect([ 23, 24, 30, 31 ].map { |day| timeline.ramp_period_for(monday + day) }).to eq([ nil, illness, illness, nil ])
    end

    it "ignores breaks without a ramp" do
      expect((10..14).map { |day| timeline.ramp_period_for(monday + day) }).to all(be_nil)
    end
  end

  describe "#latest_completed_before" do
    it "returns the period that ended most recently before the date, never one still running" do
      expect([ 7, 9, 10, 22, 24 ].map { |day| timeline.latest_completed_before(monday + day) }).to eq([ nil, nil, holiday, holiday, illness ])
    end
  end

  describe "#overlaps_week? and #periods_overlapping" do
    it "counts a week as overlapped from the break's first day through the Monday its ramp reaches" do
      overlapped = (-5..5).select { |week| timeline.overlaps_week?(monday + week * 7) }

      expect(overlapped).to eq([ 1, 3, 4 ])
    end

    it "reaches a week starting exactly on the last ramp day, but not the day after" do
      ramp = period_class.new(3, monday, monday + 1, 12)

      expect(described_class.new([ ramp ]).overlaps_week?(monday + 13)).to be(true)
      expect(described_class.new([ ramp ]).overlaps_week?(monday + 14)).to be(false)
    end

    it "does not extend a break with no ramp past its last day" do
      expect(described_class.new([ holiday ]).overlaps_week?(monday + 14)).to be(false)
      expect(described_class.new([ holiday ]).overlaps_week?(monday + 7)).to be(true)
    end

    it "returns each period that overlaps any of the weeks, once" do
      weeks = [ monday + 7, monday + 14, monday + 21 ]

      expect(timeline.periods_overlapping(weeks)).to eq([ holiday, illness ])
      expect(timeline.periods_overlapping([ monday ])).to eq([])
    end
  end

  describe "#ramp_stage" do
    it "returns the return-ramp stage for dates inside the period's ramp and nil outside it" do
      expect([ 24, 27, 28, 30, 31 ].map { |day| timeline.ramp_stage(illness, monday + day) }).to eq([ 0, 1, 2, 3, nil ])
    end

    it "returns nil for a period without a ramp" do
      expect(timeline.ramp_stage(holiday, monday + 10)).to be_nil
    end
  end
end
