require "engine_helper"

RSpec.describe Planning::V1::AssessmentSchedule do
  let(:start) { Date.new(2026, 9, 7) }
  let(:phase) { Planning::PhaseAllocator::Phase.new(kind: :build, starts_on: start, ends_on: start + 140, position: 1) }
  let(:configuration) do
    Planning::PlanConfiguration.new(
      goal: "increase_ftp",
      discipline: "road",
      starts_on: start,
      duration_mode: "custom",
      custom_duration_weeks: 20,
      ftp_watts: 260,
      include_base: false,
      progression_mode: "continuous",
      availability: (1..7).to_h { |day| [ day.to_s, { enabled: "1", weekday: day.to_s, duration_minutes: "60", intent: "threshold" } ] })
  end

  def item(offset, intent: "threshold", subtype: intent, phase: "build")
    Planning::PlanBuilder::Prescription.new(
      scheduled_on: start + offset,
      kind: :workout,
      intent: intent,
      subtype: subtype,
      duration_minutes: 60,
      phase: phase)
  end

  def dates(items, flags: {}, phases: [ phase ], config: configuration)
    described_class.new(configuration: config, phases: phases, recovery_flags: flags, prescriptions: items.sort_by(&:scheduled_on)).dates
  end

  it "ranks the first specific intensity day after recovery above ideal spacing" do
    expect(dates([ item(29), item(36) ], flags: { start + 21 => true }).first).to eq(start + 29)
  end

  it "ranks the first intensity day of a new phase above rest-preceded intensity" do
    base = Planning::PhaseAllocator::Phase.new(kind: :base, starts_on: start, ends_on: start + 37, position: 1)
    build = phase.with(starts_on: start + 38)
    expect(dates([ item(29, phase: "base"), item(36, phase: "base"), item(43), item(39) ], phases: [ base, build ]).first).to eq(start + 39)
  end

  it "prefers intensity preceded by rest or recovery, then breaks ties by ideal spacing and date" do
    items = [ item(28, intent: "endurance"), item(29), item(35, intent: "recovery"), item(36), item(40, intent: "endurance"), item(41) ]
    expect(dates(items).first).to eq(start + 36)
  end

  it "uses normal days only as fallback and permits assessments in the last 14 days of non-event plans" do
    config = configuration
    expect(dates([ item(126, intent: "endurance"), item(132, intent: "endurance") ], config: config).first).to eq(start + 126)
    expect(dates([ item(29), item(57), item(99) ])).to eq([ start + 29, start + 57, start + 99 ])
  end

  it "skips blocked dates and resumes after an unavailable 4–6 week window" do
    def configuration.assessment_blocked?(date) = false
    allow(configuration).to receive(:assessment_blocked?) { |date| date <= start + 42 }
    expect(dates([ item(29), item(36), item(50), item(78) ])).to eq([ start + 50, start + 78 ])
  end
end

RSpec.describe "FTP-001 plan assessment boundaries" do
  def preview(goal: "increase_ftp", intent: "threshold", weeks: 6)
    start = Date.new(2026, 9, 7)
    config = Planning::PlanConfiguration.new(
      goal: goal,
      discipline: "road",
      starts_on: start,
      duration_mode: "custom",
      custom_duration_weeks: weeks,
      ftp_watts: 260,
      include_base: false,
      event_name: "Event",
      event_on: start + weeks * 7 - 1,
      progression_mode: "continuous",
      availability: { "2" => { enabled: "1", weekday: "2", duration_minutes: "60", intent: intent } })
    Planning::PlanBuilder.new(config).preview
  end

  %w[threshold sweet_spot vo2_max tempo intervals endurance].each do |intent|
    it "replaces a #{intent} day in the last two weeks of a six-week non-event plan" do
      result = preview(intent: intent)
      expect(result.ftp_test_dates).to include(be_between(result.ends_on - 13, result.ends_on))
      test = result.prescriptions.find { |item| item.kind == "ftp_test" }
      expect([ test.metrics, test.definition, test.duration_minutes ]).to all(be_nil)
    end
  end

  it "excludes the full 14 days before an event and never replaces its opener" do
    result = preview(goal: "event", weeks: 12)
    expect(result.ftp_test_dates).to all(be < result.ends_on - 14)
    expect(result.prescriptions.find { |item| item.kind == "opener" }.scheduled_on).to eq(result.ends_on - 1)
  end
end
