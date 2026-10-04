require "engine_helper"

RSpec.describe Planning::V1::RecoverySchedule do
  let(:start) { Date.new(2026, 9, 7) }

  def flags(boundaries:, hard_weeks: 3, taper_on: nil, starts_on: start)
    ends = start + 90
    kinds = %w[base build speciality]
    phases = ([ starts_on ] + boundaries).each_with_index.map do |date, index|
      Planning::PhaseAllocator::Phase.new(
        kind: kinds[index],
        starts_on: date,
        ends_on: (boundaries[index] || taper_on || ends + 1) - 1,
        position: index + 1)
    end
    phases << Planning::PhaseAllocator::Phase.new(kind: :taper, starts_on: taper_on, ends_on: ends, position: 4) if taper_on
    described_class.new(starts_on: starts_on, ends_on: ends, phases: phases, hard_weeks: hard_weeks).flags
  end

  it "aligns a nearby recovery to the complete week before each phase transition and resumes the cycle" do
    result = flags(boundaries: [ start + 35, start + 70 ])
    expect(result.select { |_, recovery| recovery }.keys).to eq([ start + 28, start + 63 ])
  end

  it "aligns earlier and uses the last full week before a midweek transition" do
    expect(flags(boundaries: [ start + 21 ]).fetch(start + 14)).to be(true)
    expect(flags(boundaries: [ start + 31 ]).fetch(start + 21)).to be(true)
  end

  it "retains the cycle when transitions are distant and omits recovery overlapping taper" do
    result = flags(boundaries: [ start + 49 ], taper_on: start + 76)
    expect(result.fetch(start + 21)).to be(true)
    expect(result.fetch(start + 77)).to be(false)
  end

  it "does not create adjacent recoveries or a recovery in the first partial week" do
    result = flags(boundaries: [ start + 14, start + 21 ], hard_weeks: 1, starts_on: start + 2)
    recovery_dates = result.select { |_, recovery| recovery }.keys
    expect(result.fetch(start)).to be(false)
    expect(recovery_dates.each_cons(2).all? { |a, b| b - a >= 14 }).to be(true)
  end

  it "leaves continuous progression without scheduled recoveries" do
    expect(flags(boundaries: [ start + 28 ], hard_weeks: nil).values).to all(be(false))
  end
end
