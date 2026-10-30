require "rails_helper"

RSpec.describe Metrics::RideCalculator do
  let(:start) { Time.utc(2026, 10, 28, 11, 0, 0) }

  def sample(second, power: nil, heart_rate: nil, speed: 8.0)
    Fit::Reader::Sample.new(recorded_at: start + second, power_watts: power, heart_rate_bpm: heart_rate, speed_mps: speed)
  end

  def ride(fixture)
    samples = Fit::Reader.new(file_fixture("fit/#{fixture}.fit").binread).samples
    described_class.new(samples: samples, ftp_watts: 260).call
  end

  it "calculates a constant FTP hour like a planned workout" do
    result = described_class.new(samples: Array.new(3600) { |second| sample(second, power: 260) }, ftp_watts: 260).call

    expect(result).to have_attributes(elapsed_seconds: 3599, moving_seconds: 3599, started_at: start)
    expect(result.average_power_watts).to be_within(1e-8).of(260)
    expect(result.np_watts).to be_within(1e-8).of(260)
    expect(result.intensity_factor).to be_within(1e-8).of(1.0)
    expect(result.tss).to be_within(1e-8).of(100)
    expect(result.work_kj).to be_within(1e-8).of(936)
  end

  it "uses the same normalized power as planned estimates" do
    powers = Array.new(30, 130.0) + Array.new(30, 260.0)
    step = ->(position, pct) { Workouts::StepDefinition.new(position:, kind: "steady", label: "Fixture", duration_seconds: 30, target_low_pct_ftp: pct, target_high_pct_ftp: pct) }
    planned = Metrics::WorkoutCalculator.new(steps: [ step.(1, 50), step.(2, 100) ], ftp_watts: 260).call

    result = described_class.new(samples: powers.each_with_index.map { |power, second| sample(second, power:) }, ftp_watts: 260).call

    expect(result.np_watts).to be_within(1e-8).of(planned.estimated_np_watts)
    expect(result.tss).to be_within(1e-8).of(planned.estimated_tss)
  end

  it "counts power dropouts inside a powered ride as zero watts" do
    result = described_class.new(samples: [ sample(0, power: 200), sample(1), sample(2, power: 100) ], ftp_watts: 250).call

    expect(result.average_power_watts).to be_within(1e-8).of(100)
    expect(result.work_kj).to be_within(1e-8).of(0.3)
  end

  it "excludes stopped samples and recording pauses from moving time" do
    gap = Training::Rules::RIDE_PAUSE_GAP_SECONDS
    samples = [
      sample(0), sample(1), sample(2, speed: 0.0), sample(3, speed: 0.4), sample(4),
      sample(5 + gap), sample(6 + gap, speed: nil), sample(6 + 2 * gap)
    ]

    result = described_class.new(samples:, ftp_watts: 260).call

    # Counted: 0->1, 3->4, 5+gap->6+gap (unknown speed), and an exact pause-gap step.
    expect(result.moving_seconds).to eq(1 + 1 + 1 + gap)
    expect(result.elapsed_seconds).to eq(6 + 2 * gap)
  end

  it "averages recorded heart rate and ignores missing or zero readings" do
    samples = [ sample(0, heart_rate: 140), sample(1), sample(2, heart_rate: 0), sample(3, heart_rate: 150) ]

    expect(described_class.new(samples:, ftp_watts: 260).call.average_heart_rate_bpm).to eq(145)
  end

  it "returns no power metrics or heart rate when neither was recorded" do
    result = described_class.new(samples: [ sample(0), sample(1) ], ftp_watts: 260).call

    expect(result).to have_attributes(
      average_power_watts: nil,
      np_watts: nil,
      intensity_factor: nil,
      tss: nil,
      work_kj: nil,
      average_heart_rate_bpm: nil,
      elapsed_seconds: 1,
      moving_seconds: 1)
  end

  it "rejects an empty ride and an invalid FTP" do
    expect { described_class.new(samples: [], ftp_watts: 260) }.to raise_error(ArgumentError)
    expect { described_class.new(samples: [ sample(0) ], ftp_watts: 0) }.to raise_error(ArgumentError)
  end

  describe "recorded fixtures" do
    # The head unit's own session summary for this ride reports NP 228,
    # IF 0.877, average power 165 W, work 484.2 kJ and average HR 142.
    it "matches the head unit's summary for an outdoor ride with stops" do
      result = ride("outdoor_ride")

      expect(result.np_watts).to be_within(1).of(228)
      expect(result.intensity_factor).to be_within(0.005).of(0.877)
      expect(result.average_power_watts).to be_within(0.5).of(165)
      expect(result.work_kj).to be_within(0.5).of(484.2)
      expect(result.average_heart_rate_bpm).to be_within(0.5).of(142)
      expect(result.tss).to be_within(1).of(62.1)
      expect(result).to have_attributes(elapsed_seconds: 2934, moving_seconds: 2817)
    end

    it "matches the trainer app's summary for an indoor ride" do
      result = ride("indoor_ride")

      expect(result.average_power_watts).to be_within(0.5).of(165)
      expect(result.average_heart_rate_bpm).to be_within(0.5).of(143)
      expect(result).to have_attributes(elapsed_seconds: 2715, moving_seconds: 2715)
      expect(result.tss).to be_within(0.1).of(37.8)
    end

    it "keeps duration and heart rate for a ride without power" do
      result = ride("outdoor_ride_without_power")

      expect(result).to have_attributes(tss: nil, np_watts: nil, elapsed_seconds: 2934, moving_seconds: 2817)
      expect(result.average_heart_rate_bpm).to be_within(0.5).of(142)
    end
  end
end
