require "engine_helper"
require_relative "../../app/services/training/progression"

RSpec.describe Training::Progression do
  [ [ 3, 0, 3 ], [ 3, -1, 2 ], [ 3, 1, 4 ], [ 1, -2, 1 ], [ 7, 2, 7 ], [ 3, 9, 5 ], [ 3, -9, 1 ] ].each do |baseline, bias, expected|
    it "maps baseline #{baseline} and bias #{bias} to #{expected}" do
      expect(described_class.level(baseline: baseline, bias: bias)).to eq(expected)
    end
  end

  it "applies the effective re-entry or load ceiling after feedback" do
    expect(described_class.level(baseline: 6, bias: -1, maximum: 3)).to eq(3)
    expect(described_class.level(baseline: 6, bias: 2, maximum: 3)).to eq(3)
  end
end
