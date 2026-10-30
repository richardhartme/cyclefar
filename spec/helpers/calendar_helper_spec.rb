require "rails_helper"

RSpec.describe CalendarHelper, type: :helper do
  describe "#weekly_duration" do
    it "shows weekly totals in hours and minutes" do
      expect(helper.weekly_duration(330)).to eq("5 h 30 min")
      expect(helper.weekly_duration(120)).to eq("2 h 00 min")
      expect(helper.weekly_duration(65)).to eq("1 h 05 min")
      expect(helper.weekly_duration(45)).to eq("45 min")
      expect(helper.weekly_duration(0)).to eq("0 min")
    end
  end

  describe "workout profile zone colours" do
    it "maps FTP-target boundaries to the graph palette" do
      expect(helper.send(:profile_zone_color, segment_at(55))).to eq("#94A3B8")
      expect(helper.send(:profile_zone_color, segment_at(56))).to eq("#38BDF8")
      expect(helper.send(:profile_zone_color, segment_at(76))).to eq("#14B8A6")
      expect(helper.send(:profile_zone_color, segment_at(88))).to eq("#22C55E")
      expect(helper.send(:profile_zone_color, segment_at(95))).to eq("#F59E0B")
      expect(helper.send(:profile_zone_color, segment_at(106))).to eq("#F97316")
      expect(helper.send(:profile_zone_color, segment_at(121))).to eq("#EF4444")
    end
  end

  def segment_at(percentage)
    Workouts::ProfileBuilder::Segment.new(
      position: 1,
      label: "Test",
      kind: "steady",
      starts_at_seconds: 0,
      ends_at_seconds: 60,
      start_low_pct_ftp: percentage,
      start_high_pct_ftp: percentage,
      end_low_pct_ftp: percentage,
      end_high_pct_ftp: percentage)
  end
end
