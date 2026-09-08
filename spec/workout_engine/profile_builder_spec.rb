require "engine_helper"

RSpec.describe Workouts::ProfileBuilder do
  it "WKO-001 derives a continuous time axis with exact range endpoints" do
    ramp = Workouts::StepDefinition.new(
      kind: "ramp",
      label: "Warm-up",
      duration_seconds: 300,
      target_low_pct_ftp: 45,
      target_high_pct_ftp: 55,
      end_target_low_pct_ftp: 65,
      end_target_high_pct_ftp: 70)
    steady = Workouts::StepDefinition.new(
      position: 2,
      kind: "steady",
      label: "Endurance",
      duration_seconds: 900,
      target_low_pct_ftp: 60,
      target_high_pct_ftp: 72)
    profile = described_class.new(steps: [ ramp, steady ]).call
    expect(profile.duration_seconds).to eq(1200)
    expect(profile.segments.first).to have_attributes(
      starts_at_seconds: 0,
      ends_at_seconds: 300,
      start_low_pct_ftp: 45,
      start_high_pct_ftp: 55,
      end_low_pct_ftp: 65,
      end_high_pct_ftp: 70)
    expect(profile.segments.last).to have_attributes(
      starts_at_seconds: 300,
      ends_at_seconds: 1200,
      start_low_pct_ftp: 60,
      start_high_pct_ftp: 72,
      end_low_pct_ftp: 60,
      end_high_pct_ftp: 72)
    expect { profile.segments.clear }.to raise_error(FrozenError)
  end

  it "sorts canonical positions and leaves supplied hashes untouched" do
    workout = Workouts::Generator.new(subtype: :over_under, duration_minutes: 60, progression_level: 3).call
    attributes = workout.steps.map(&:to_h).reverse
    original = Marshal.load(Marshal.dump(attributes))
    profile = described_class.new(steps: attributes).call
    expect(profile).to eq(described_class.new(steps: workout.steps).call)
    expect(attributes).to eq(original)
    expect(profile.segments.each_cons(2).all? { |a, b| a.ends_at_seconds == b.starts_at_seconds }).to be(true)
    expect(profile.segments.last.ends_at_seconds).to eq(3600)
  end
end
