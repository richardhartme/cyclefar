require "engine_helper"
require_relative "../../app/services/planning/v1/phase_progression"

RSpec.describe Planning::V1::PhaseProgression do
  let(:starts_on) { Date.new(2026, 9, 7) }

  { base: [ 1, 4 ], build: [ 3, 6 ], speciality: [ 4, 7 ], taper: [ 1, 2 ] }.each do |kind, (first, last)|
    it "uses the #{kind} range at both phase boundaries" do
      attributes = { kind: kind, starts_on: starts_on, ends_on: starts_on + 27 }
      expect(described_class.level(**attributes, date: starts_on)).to eq(first)
      expect(described_class.level(**attributes, date: starts_on + 27)).to eq(last)
      expect(described_class.level(**attributes, date: starts_on + 14)).to eq(first + (last - first + 1) / 2)
    end
  end

  it "handles a single-day phase without dividing by zero" do
    expect(described_class.level(kind: :build, starts_on: starts_on, ends_on: starts_on, date: starts_on)).to eq(3)
  end
end
