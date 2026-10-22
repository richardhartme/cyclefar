require "rails_helper"

RSpec.describe Planning::ReturnRamp do
  let(:ends_on) { Date.new(2026, 10, 5) }
  let(:ramp) { described_class.new(ends_on: ends_on, days: 16) }

  it "advances one stage per quarter of the ramp" do
    stages = [ 1, 4, 5, 8, 9, 12, 13 ].map { |offset| ramp.stage_on(ends_on + offset) }

    expect(stages).to eq([ 0, 0, 1, 1, 2, 2, 3 ])
  end

  it "never exceeds the final stage" do
    expect(ramp.stage_on(ends_on + 60)).to eq(Planning::Rules::RETURN_RAMP_FINAL_STAGE)
  end

  it "has one duration factor per stage" do
    expect(Planning::Rules::RETURN_RAMP_DURATION_FACTORS.size).to eq(Planning::Rules::RETURN_RAMP_STAGE_COUNT)
  end
end
