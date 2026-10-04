require "engine_helper"
require_relative "../../app/services/planning/v1/return_ramp"

RSpec.describe Planning::V1::ReturnRamp do
  let(:ends_on) { Date.new(2026, 10, 4) }
  let(:ramp) { described_class.new(ends_on: ends_on, days: 16) }

  it "OFF-001 divides the selected calendar duration into four deterministic stages" do
    expect((1..16).map { |day| ramp.stage_on(ends_on + day) }).to eq([ 0 ] * 4 + [ 1 ] * 4 + [ 2 ] * 4 + [ 3 ] * 4)
    expect([ 1, 5, 9, 13 ].map { |day| ramp.duration_factor(ends_on + day) }).to eq([ 0.60, 0.70, 0.80, 1.0 ])
    expect(ramp.target_band(ends_on + 1, intensity: true)).to eq([ 45, 60 ])
    expect(ramp.target_band(ends_on + 5, intensity: false)).to eq([ 55, 68 ])
    expect(ramp.target_band(ends_on + 9, intensity: true)).to eq([ 78, 87 ])
    expect(ramp.target_band(ends_on + 9, intensity: false)).to be_nil
    expect(ramp.target_band(ends_on + 13, intensity: true)).to be_nil
  end

  { 1 => [ 0 ], 2 => [ 0, 2 ], 3 => [ 0, 1, 2 ], 5 => [ 0, 0, 1, 2, 3 ] }.each do |days, stages|
    it "OFF-001 collapses a #{days}-day ramp without adding calendar dates" do
      short = described_class.new(ends_on: ends_on, days: days)
      expect((1..days).map { |day| short.stage_on(ends_on + day) }).to eq(stages)
    end
  end

  it "OFF-001 holds a reduced level during the ramp and resumes weekly progression after it" do
    expect([ 13, 16, 17, 23, 24, 31 ].map { |day| ramp.progression_level(ends_on + day, baseline: 4) }).to eq([ 3, 3, 3, 3, 4, 5 ])
    expect(ramp.progression_level(ends_on + 16, baseline: 1)).to eq(1)
    expect(ramp.progression_level(ends_on + 100, baseline: 7)).to eq(7)
  end
end
