require "rails_helper"

# The spike's raw payloads (#51) were not kept, so the fixture is rebuilt
# from the shapes, units and figures it recorded (docs/GARMIN_CONNECT.md):
# its ids and most values are illustrative, with no GPS, device or owner
# fields. Replace it with redacted real payloads when they are captured.
RSpec.describe GarminConnect::ActivitySummary do
  let(:payloads) { JSON.parse(file_fixture("garmin_connect/activities.json").read) }
  let(:ride_payload) { payloads.first }

  it "reads a Zwift ride's identity, start, durations, distance, heart rate and power" do
    summary = described_class.from_payload(ride_payload)

    expect(summary).to have_attributes(
      garmin_activity_id: 25_012_345_678,
      name: "Zwift - Watopia",
      external_type: "virtual_ride",
      sport: "cycling",
      started_at: Time.utc(2026, 11, 10, 18, 30, 12),
      started_on: Date.new(2026, 11, 10),
      duration_seconds: 2712,
      elapsed_seconds: 2712,
      moving_seconds: 2700,
      distance_metres: 22_451.37,
      average_heart_rate_bpm: 140.0,
      max_heart_rate_bpm: 166.0,
      average_power_watts: 155.0,
      np_watts: 158.4,
      max_power_watts: 412.0,
      payload: ride_payload)
  end

  it "leaves figures Garmin did not send empty and keeps the whole summary for later stages" do
    yoga = described_class.from_payload(payloads.second)

    expect(yoga).to have_attributes(moving_seconds: nil, average_power_watts: nil, np_watts: nil)
    expect(yoga.payload).to include("activityTrainingLoad" => 4.1, "manufacturer" => "GARMIN")
  end

  it "rejects a summary without a usable id, type or start time" do
    broken = [
      [ ride_payload ],
      ride_payload.except("activityId"),
      ride_payload.merge("activityId" => "25012345678"),
      ride_payload.except("activityType"),
      ride_payload.merge("startTimeGMT" => nil),
      ride_payload.merge("startTimeLocal" => "10/11/2026 18:30"),
      ride_payload.merge("startTimeLocal" => "2026-11-12 18:30:12")
    ]

    broken.each do |payload|
      expect { described_class.from_payload(payload) }.to raise_error(GarminConnect::ActivitySummary::InvalidPayload)
    end
  end

  it "schedules by the local date and derives the UTC offset from local minus GMT" do
    payload = ride_payload.merge("startTimeLocal" => "2026-07-01 00:30:05", "startTimeGMT" => "2026-06-30 23:30:05")

    summary = described_class.from_payload(payload)

    expect(summary.started_at).to eq(Time.utc(2026, 6, 30, 23, 30, 5))
    expect(summary.started_on).to eq(Date.new(2026, 7, 1))
    expect(summary.local_started_at.utc_offset).to eq(3600)
    expect(summary.local_started_at.strftime("%F %T %:z")).to eq("2026-07-01 00:30:05 +01:00")
  end

  describe "GAR-006 sport mapping" do
    def summary_for(type_key, type_id:, parent_type_id:)
      described_class.from_payload(
        ride_payload.merge(
          "activityType" => { "typeKey" => type_key, "typeId" => type_id, "parentTypeId" => parent_type_id }))
    end

    # Only virtual_ride was seen in the spike; the other keys and ids are
    # unconfirmed and stand for any type under the cycling parent.
    it "maps every type under the cycling parent to cycling, without relying on fixed type ids" do
      rides = { "road_biking" => 10, "indoor_cycling" => 25, "virtual_ride" => 152, "gravel_cycling" => 143, "mountain_biking" => 5, "future_bike_type" => 9999 }

      rides.each do |type_key, type_id|
        expect(summary_for(type_key, type_id: type_id, parent_type_id: 2)).to have_attributes(sport: "cycling", external_type: type_key)
      end
    end

    it "maps the cycling type itself to cycling" do
      expect(summary_for("cycling", type_id: 2, parent_type_id: 17).sport).to eq("cycling")
    end

    it "maps the strength and yoga keys seen in the spike" do
      expect(payloads.drop(1).map { |payload| described_class.from_payload(payload).sport }).to eq(%w[yoga strength])
    end

    it "maps only to sports the Activity model accepts" do
      expect(Activity::SPORTS).to include("cycling", "other", *GarminConnect::SportMapping::TYPE_KEYS.values)
    end

    it "maps unknown keys to other and keeps the raw key" do
      summary = summary_for("hiking", type_id: 3, parent_type_id: 17)

      expect(summary).to have_attributes(sport: "other", external_type: "hiking")
    end
  end
end
