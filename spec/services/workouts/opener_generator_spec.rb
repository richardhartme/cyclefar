require "rails_helper"

RSpec.describe Workouts::OpenerGenerator do
  def summary(definition)
    definition.steps.map do |step|
      [ step.kind, step.duration_seconds, step.target_low_pct_ftp, step.target_high_pct_ftp, step.end_target_low_pct_ftp, step.end_target_high_pct_ftp ]
    end
  end

  it "builds the §45 activation structure fitted exactly to the duration" do
    definition = described_class.new(duration_minutes: 40).call

    expect(summary(definition)).to eq(
      [
        [ "ramp", 600, 45, 55, 70, 70 ],
        *Array.new(3) { [ [ "steady", 60, 100, 108, nil, nil ], [ "steady", 120, 50, 60, nil, nil ] ] }.flatten(1),
        *Array.new(3) { [ [ "steady", 30, 108, 118, nil, nil ], [ "steady", 90, 50, 60, nil, nil ] ] }.flatten(1),
        [ "steady", 600, 50, 65, nil, nil ],
        [ "ramp", 300, 55, 60, 40, 50 ]
      ])
    expect(definition.steps.sum(&:duration_seconds)).to eq(40 * 60)
    expect(definition.name).to eq("Event Opener")
  end

  it "rejects durations outside 30 to 45 minutes" do
    expect { described_class.new(duration_minutes: 29) }.to raise_error(ArgumentError, "opener duration must be 30 to 45 minutes")
    expect { described_class.new(duration_minutes: 46) }.to raise_error(ArgumentError)
    expect { described_class.new(duration_minutes: 45) }.not_to raise_error
  end
end
