require "engine_helper"

RSpec.describe Planning::PlanBuilder do
  def availability(days = { 1 => [ 60, "intervals" ], 3 => [ 90, "endurance" ], 6 => [ 60, "intervals" ] })
    days.to_h do |weekday, (duration, intent)|
      [ weekday.to_s, { enabled: "1", weekday: weekday.to_s, duration_minutes: duration.to_s, intent: intent } ]
    end
  end

  def configuration(**attributes)
    defaults = {
      goal: "increase_ftp", discipline: "road", starts_on: Date.new(2026, 9, 7), duration_mode: "preset",
      duration_months: 3, ftp_watts: 260, include_base: true, progression_mode: "continuous", availability: availability
    }
    Planning::PlanConfiguration.new(**defaults.merge(attributes))
  end

  def preview(**attributes)
    config = configuration(**attributes)
    expect(config).to be_valid
    described_class.new(config).preview
  end

  it "PLN-010 validates all supported goals, disciplines and a repeating availability template" do
    Training::V1::Rules::GOALS.product(Training::V1::Rules::DISCIPLINES).each do |goal, discipline|
      attributes = goal == "event" ? { event_name: "Test Event", event_on: Date.new(2026, 10, 12), event_discipline: discipline } : {}
      expect(configuration(goal: goal, discipline: discipline, **attributes)).to be_valid
    end
    invalid = configuration(availability: {})
    expect(invalid).not_to be_valid
    expect(invalid.errors[:availability]).to include("must include at least one training day")
  end

  it "PLN-010 uses calendar-month presets and custom whole-week durations" do
    start = Date.new(2026, 1, 31)
    expect(preview(starts_on: start, duration_months: 1).ends_on).to eq(Date.new(2026, 2, 27))
    expect(preview(starts_on: start, duration_months: 3).ends_on).to eq(Date.new(2026, 4, 29))
    expect(preview(starts_on: start, duration_months: 6).ends_on).to eq(Date.new(2026, 7, 30))
    expect(preview(starts_on: start, duration_mode: "custom", custom_duration_weeks: 4).ends_on).to eq(Date.new(2026, 2, 27))
    expect(configuration(duration_mode: "custom", custom_duration_weeks: 3)).not_to be_valid
  end

  it "PLN-020 allocates contiguous Base, Build and Speciality phases, or skips Base" do
    with_base = preview
    without_base = preview(include_base: false)
    expect(with_base.phases.map(&:kind)).to eq(%w[base build speciality])
    expect(without_base.phases.map(&:kind)).to eq(%w[build speciality])
    [ with_base, without_base ].each do |plan|
      expect(plan.phases.first.starts_on).to eq(plan.starts_on)
      expect(plan.phases.last.ends_on).to eq(plan.ends_on)
      expect(plan.phases.each_cons(2).all? { |first, second| first.ends_on + 1 == second.starts_on }).to be(true)
    end
  end

  it "PLN-012 overlays N hard weeks then one recovery week without a cycle in continuous mode" do
    cycled = preview(progression_mode: "hard_recovery_cycle", hard_weeks_before_recovery: 3, duration_months: 3)
    continuous = preview(progression_mode: "continuous", duration_months: 3)
    expect(cycled.weeks.map(&:recovery_week)).to eq([ false, false, false, true, false, false, false, true, false, false, false, true, false ])
    expect(continuous.weeks.map(&:recovery_week)).to all(be(false))
    recovery = cycled.weeks.select(&:recovery_week)
    hard = cycled.weeks.reject(&:recovery_week)
    expect(recovery.map(&:estimated_tss).max).to be < hard.map(&:estimated_tss).max
    expect(recovery.flat_map(&:prescriptions).select(&:executable?).map(&:subtype).uniq).to all(be_in(%w[endurance recovery]))
  end

  it "selects broad interval cycles deterministically and preserves specific intents" do
    broad = preview(
      goal: "improve_climbing",
      include_base: false,
      availability: availability(1 => [ 60, "intervals" ], 3 => [ 60, "intervals" ]))
    build = broad.prescriptions.select { |item| item.phase == "build" && item.intent == "intervals" }.map(&:subtype)
    expect(build.first(4)).to eq(%w[threshold vo2_max over_under threshold])
    specific = preview(availability: availability(2 => [ 60, "threshold" ], 5 => [ 90, "endurance" ]))
    expect(specific.prescriptions.select { |item| item.intent == "threshold" }.map(&:subtype).uniq).to eq([ "threshold" ])
  end

  it "PLN-022 adds a 7 or 14 day taper, keeps the target event fixed and places a low-load opener" do
    event_attributes = { goal: "event", event_name: "Autumn Classic", event_on: Date.new(2026, 12, 6), event_discipline: "road" }
    short_taper = preview(**event_attributes)
    long_taper = preview(**event_attributes.merge(event_expected_duration_minutes: 360))
    expect(short_taper.phases.last.kind).to eq("taper")
    expect(short_taper.phases.last.ends_on).to eq(Date.new(2026, 12, 6))
    expect(short_taper.phases.last.starts_on).to eq(Date.new(2026, 11, 30))
    expect(long_taper.phases.last.starts_on).to eq(Date.new(2026, 11, 23))
    opener = long_taper.prescriptions.find { |item| item.kind == "opener" }
    expect(opener.scheduled_on).to eq(Date.new(2026, 12, 5))
    expect(opener.duration_minutes).to be_between(30, 45)
    expect(opener.metrics.estimated_tss).to be < 40
    expect(long_taper.prescriptions.find { |item| item.kind == "event" }.scheduled_on).to eq(Date.new(2026, 12, 6))
  end

  it "places no routine FTP test in short plans and replaces eligible workout days every four to six weeks in longer plans" do
    expect(preview(duration_mode: "custom", custom_duration_weeks: 5).ftp_test_dates).to be_empty
    long = preview(duration_months: 6)
    expect(long.ftp_test_dates).not_to be_empty
    expect(long.ftp_test_dates.each_cons(2).all? { |first, second| (second - first).between?(28, 42) }).to be(true)
    long.ftp_test_dates.each do |date|
      item = long.prescriptions.find { |prescription| prescription.scheduled_on == date }
      expect(item.kind).to eq("ftp_test")
      expect(item.metrics).to be_nil
    end
  end

  it "PLN-013 caps generated comparable hard-week load growth at 8% when the schedule permits" do
    plan = preview(duration_months: 6)
    comparable = plan.weeks.reject do |week|
      week.partial || week.recovery_week || week.phase == "taper" || week.warning || week.prescriptions.any? { |item| item.kind == "ftp_test" }
    end
    expect(comparable.each_cons(2).all? { |first, second| second.estimated_tss <= first.estimated_tss * 1.08 + 1e-8 }).to be(true)
  end

  it "returns immutable in-memory preview data" do
    plan = preview
    expect { plan.phases << plan.phases.first }.to raise_error(FrozenError)
    expect { plan.weeks.first.prescriptions << plan.weeks.first.prescriptions.first }.to raise_error(FrozenError)
  end
end
