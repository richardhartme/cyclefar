require "engine_helper"

RSpec.describe "PLN-022 staged taper" do
  let(:start) { Date.new(2026, 9, 7) }
  let(:event) { Date.new(2026, 12, 6) }

  def configuration(long: true)
    Planning::PlanConfiguration.new(
      goal: "event",
      discipline: "road",
      starts_on: start,
      event_name: "Autumn Classic",
      event_on: event,
      event_expected_duration_minutes: long ? 360 : 120,
      ftp_watts: 260,
      include_base: true,
      progression_mode: "continuous",
      availability: { "2" => { enabled: "1", weekday: "2", duration_minutes: "60", intent: "threshold" },
              "4" => { enabled: "1", weekday: "4", duration_minutes: "90", intent: "endurance" },
              "6" => { enabled: "1", weekday: "6", duration_minutes: "60", intent: "vo2_max" },
              "7" => { enabled: "1", weekday: "7", duration_minutes: "120", intent: "endurance" } })
  end

  def peak(preview)
    preview.weeks.reject { |week| week.partial || week.recovery_week || week.prescriptions.any? { |item| %w[ftp_test event opener].include?(item.kind) || item.phase == "taper" } }.map(&:estimated_tss).max
  end

  it "uses 70–80% peak load in the first long-taper stage and 40–60% in event week, including the opener" do
    preview = Planning::PlanBuilder.new(configuration).preview
    reference = peak(preview)
    expect(preview.weeks[-2].estimated_tss / reference).to be_between(0.70, 0.80)
    expect(preview.weeks[-1].estimated_tss / reference).to be_between(0.40, 0.60)
    first = preview.weeks[-2].prescriptions.select(&:intensity?)
    last = preview.weeks[-1].prescriptions.select(&:intensity?)
    expect(first.map(&:subtype)).to eq(%w[threshold vo2_max])
    expect(last.map(&:subtype)).to eq([ "threshold" ])
    expect(first.map { |item| item.definition.load_adjustments.fetch("main_set_factor") }).to all(eq(0.75))
    expect(last.sole.definition.load_adjustments.fetch("main_set_factor")).to eq(0.60)
    expect(preview.prescriptions.find { |item| item.kind == "opener" }.scheduled_on).to eq(event - 1)
    expect(preview.prescriptions.find { |item| item.kind == "event" }.scheduled_on).to eq(event)
    expect(preview.prescriptions.select { |item| item.kind == "workout" && item.scheduled_on >= event - 2 }).not_to include(have_attributes(subtype: "vo2_max"))
  end

  it "keeps one early reduced intensity session in a seven-day taper, with no hard ride in the final 48 hours" do
    preview = Planning::PlanBuilder.new(configuration(long: false)).preview
    taper = preview.prescriptions.select { |item| item.phase == "taper" && item.kind == "workout" }
    intensity = taper.select(&:intensity?).sole
    expect(intensity.scheduled_on).to eq(event - 5)
    expect(intensity.definition.steps.select { |step| step.group_key == "main" }.sum(&:duration_seconds)).to be > 0
    expect(taper.select { |item| item.scheduled_on >= event - 2 }.map(&:subtype)).to all(be_in(%w[endurance recovery]))
    expect(preview.weeks.last.estimated_tss / peak(preview)).to be_between(0.40, 0.60)
    taper.each do |item|
      expect(item.definition.steps.sum(&:duration_seconds)).to eq(item.duration_minutes * 60)
      expect(item.definition.steps.map(&:duration_seconds)).to all(be > 0)
      expect(item.definition.steps.map(&:target_high_pct_ftp)).to all(be <= 120)
    end
  end

  it "uses the same stages for a ten-day taper and non-Sunday events" do
    config = configuration
    config.event_on = event - 2
    config.availability += [ Planning::Availability.new(weekday: 3, duration_minutes: 60, intent: :threshold) ]
    allocator = Planning::PhaseAllocator.new(config).call
    taper = allocator.last.with(starts_on: config.event_on - 9)
    phases = allocator[0...-1]
    phases[-1] = phases.last.with(ends_on: taper.starts_on - 1)
    allow(Planning::PhaseAllocator).to receive(:new).with(config).and_return(double(call: phases + [ taper ]))
    preview = Planning::PlanBuilder.new(config).preview
    taper_items = preview.prescriptions.select { |item| item.phase == "taper" && item.kind == "workout" }
    expect(taper_items.select(&:intensity?).map { |item| item.definition.load_adjustments.fetch("main_set_factor") }).to eq([ 0.75, 0.60 ])
    expect(taper_items.select(&:intensity?).map(&:scheduled_on)).to all(be < config.event_on - 2)
    expect(preview.prescriptions.find { |item| item.kind == "opener" }.scheduled_on).to eq(config.event_on - 1)
  end

  it "returns identical forecasts on repeated previews" do
    config = configuration
    first = Planning::PlanBuilder.new(config).preview
    second = Planning::PlanBuilder.new(config).preview
    expect(first).to eq(second)
  end
end
