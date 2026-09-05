require "engine_helper"

RSpec.describe Metrics::WorkoutCalculator do
  def steady(duration: 3600, low: 100, high: low, position: 1)
    Workouts::StepDefinition.new(position: position, kind: "steady", label: "Fixture",
      duration_seconds: duration, target_low_pct_ftp: low, target_high_pct_ftp: high)
  end

  [ [ 100, 1.0, 100, 936 ], [ 50, 0.5, 25, 468 ] ].each do |pct, intensity, tss, work|
    it "LOAD-001 calculates a constant #{pct}% FTP hour" do
      result = described_class.new(steps: [ steady(low: pct) ], ftp_watts: 260).call
      expect(result.estimated_np_watts).to be_within(1e-8).of(260 * pct / 100.0)
      expect(result.average_power_watts).to be_within(1e-8).of(260 * pct / 100.0)
      expect(result.estimated_if).to be_within(1e-8).of(intensity)
      expect(result.estimated_tss).to be_within(1e-8).of(tss)
      expect(result.estimated_work_kj).to be_within(1e-8).of(work)
    end
  end

  it "LOAD-001 uses range midpoints" do
    result = described_class.new(steps: [ steady(low: 60, high: 80) ], ftp_watts: 200).call
    expect(result.estimated_np_watts).to be_within(1e-8).of(140)
    expect(result.estimated_tss).to be_within(1e-8).of(49)
    expect(result.estimated_work_kj).to be_within(1e-8).of(504)
  end

  it "LOAD-001 samples ramps at one-second centres and uses progressive initial windows" do
    ramp = steady(duration: 4, low: 40, high: 50).with(kind: "ramp", end_target_low_pct_ftp: 70, end_target_high_pct_ftp: 80)
    # Midpoint powers at second centres: 48.75, 56.25, 63.75, 71.25 W.
    # The growing rolling means are 48.75, 52.5, 56.25, 60 W.
    result = described_class.new(steps: [ ramp ], ftp_watts: 100).call
    expected_np = ((48.75**4 + 52.5**4 + 56.25**4 + 60**4) / 4.0)**0.25
    expect(result.estimated_np_watts).to be_within(1e-8).of(expected_np)
    expect(result.estimated_work_kj).to be_within(1e-8).of(0.240)
    expect(result.average_power_watts).to be_within(1e-8).of(60)
  end

  it "LOAD-001 carries the rolling window across step boundaries and evicts after 30 seconds" do
    steps = [ steady(duration: 30, low: 50), steady(duration: 30, low: 100, position: 2) ]
    expected_np = ((30 * 50.0**4 + (1..30).sum { |n| (50 + 50 * n / 30.0)**4 }) / 60.0)**0.25
    result = described_class.new(steps: steps, ftp_watts: 100).call
    expect(result.estimated_np_watts).to be_within(1e-8).of(expected_np)
    expect(result.estimated_work_kj).to eq(4.5)
  end

  it "SET-001 scales watts and work with FTP while IF, TSS and structure stay unchanged" do
    workout = Workouts::Generator.new(subtype: :vo2_max, duration_minutes: 60, progression_level: 5).call
    first = described_class.new(steps: workout.steps, ftp_watts: 200).call
    second = described_class.new(steps: workout.steps, ftp_watts: 300).call
    expect(second.estimated_np_watts).to be_within(1e-8).of(first.estimated_np_watts * 1.5)
    expect(second.estimated_work_kj).to be_within(1e-8).of(first.estimated_work_kj * 1.5)
    expect(second.estimated_if).to be_within(1e-8).of(first.estimated_if)
    expect(second.estimated_tss).to be_within(1e-8).of(first.estimated_tss)
    expect(workout).to eq(Workouts::Generator.new(subtype: :vo2_max, duration_minutes: 60, progression_level: 5).call)
  end

  it "accepts canonical attribute hashes without Active Record" do
    result = described_class.new(steps: [ steady.to_h ], ftp_watts: 260).call
    expect(result.estimated_if).to eq(1)
  end

  [ 0, -1, nil, 200.5, "260" ].each do |ftp|
    it "rejects invalid FTP #{ftp.inspect}" do
      expect { described_class.new(steps: [ steady ], ftp_watts: ftp).call }.to raise_error(ArgumentError)
    end
  end

  it "rejects empty structures such as unprescribed FTP tests" do
    expect { described_class.new(steps: [], ftp_watts: 260).call }.to raise_error(ArgumentError)
  end
end
