require "engine_helper"

RSpec.describe Workouts::StepDefinition do
  let(:attributes) do
    { kind: "steady", label: "Endurance", duration_seconds: 60, target_low_pct_ftp: 60, target_high_pct_ftp: 72 }
  end

  it "SET-001 derives rounded watt ranges without changing percentages" do
    step = described_class.new(**attributes)
    expect(step.target_watts(ftp_watts: 260)).to eq(low_watts: 156, high_watts: 187, end_low_watts: nil, end_high_watts: nil)
    expect(step.target_watts(ftp_watts: 300)).to include(low_watts: 180, high_watts: 216)
    expect(step.target_high_pct_ftp).to eq(72)
  end

  it "derives ramp endpoint watts and handles a one-second ramp" do
    step = described_class.new(**attributes, duration_seconds: 1, kind: "ramp", end_target_low_pct_ftp: 40, end_target_high_pct_ftp: 50)
    expect(step.target_watts(ftp_watts: 260)).to include(end_low_watts: 104, end_high_watts: 130)
    expect(step.representative_pct_at(0)).to eq(55.5)
  end

  [ { duration_seconds: 0 }, { duration_seconds: 1.5 }, { position: 0 }, { kind: "repeat" },
    { label: "" }, { target_low_pct_ftp: nil }, { target_low_pct_ftp: "60" },
    { target_high_pct_ftp: Float::INFINITY }, { target_high_pct_ftp: Float::NAN },
    { target_low_pct_ftp: 80 }, { kind: "ramp" }, { end_target_low_pct_ftp: 50 },
    { group_iteration: 0 } ].each do |invalid|
    it "rejects invalid canonical input #{invalid.inspect}" do
      expect { described_class.new(**attributes.merge(invalid)) }.to raise_error(ArgumentError)
    end
  end

  it "copies caller-owned strings before freezing its own values" do
    label = "Mutable label"
    step = described_class.new(**attributes, label: label)
    label.replace("Changed")
    expect(step.label).to eq("Mutable label")
    expect(label).not_to be_frozen
  end

  it "rejects invalid sample indexes and FTP" do
    step = described_class.new(**attributes)
    [ -1, 60, 0.5 ].each { |second| expect { step.representative_pct_at(second) }.to raise_error(ArgumentError) }
    expect { step.target_watts(ftp_watts: 0) }.to raise_error(ArgumentError)
  end

  it "rejects duplicated positions and gaps in canonical sequences" do
    step = described_class.new(**attributes)
    expect { Workouts::StepSequence.normalize([ step, step ]) }.to raise_error(ArgumentError)
    expect { Workouts::StepSequence.normalize([ step.with(position: 2) ]) }.to raise_error(ArgumentError)
  end
end
