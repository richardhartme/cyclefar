require "engine_helper"

RSpec.describe Planning::PlanConfiguration do
  def configuration(**attributes)
    described_class.new(
      { goal: "event", discipline: "road", event_discipline: "mtb",
            event_name: "Trail race", event_on: Date.new(2026, 12, 6), starts_on: Date.new(2026, 9, 7),
            ftp_watts: 260, include_base: true,
            availability: { "2" => { enabled: "1", weekday: "2", duration_minutes: "60", intent: "intervals" } } }.merge(attributes))
  end

  it "CYF-85 gives event discipline precedence while retaining the non-event selection for editing" do
    config = configuration
    expect(config).to be_valid
    expect(config).to have_attributes(discipline: "road", event_discipline: "mtb", training_discipline: "mtb")
  end

  it "CYF-85 accepts event-only input and ignores an invalid inactive non-event discipline" do
    [ nil, "unknown" ].each do |discipline|
      config = configuration(discipline: discipline)
      expect(config).to be_valid
      expect(config.training_discipline).to eq("mtb")
    end
  end

  it "CYF-86 rejects a missing or invalid event choice without inferring stale discipline" do
    [ nil, "", "unknown" ].each do |choice|
      config = configuration(discipline: "gravel", event_discipline: choice)
      expect(config).not_to be_valid
      expect(config.errors[:event_discipline]).to include("is invalid")
    end
  end

  Training::Rules::GOALS.reject { |goal| goal == "event" }.each do |goal|
    it "PLN-010 uses the internal default for #{goal}, ignoring inactive discipline and event inputs" do
      [ nil, "", "unknown", "gravel" ].each do |discipline|
        config = configuration(
          goal: goal,
          discipline: discipline,
          event_discipline: "unknown",
          event_on: "invalid",
          event_distance_km: -1,
          event_elevation_m: -1,
          event_expected_duration_minutes: -1)
        expect(config).to be_valid
        expect(config.training_discipline).to eq("road")
        expect(config.ends_on).to eq(Date.new(2026, 12, 6))
      end
    end
  end

  it "PLN-010 event dates ignore absent and stale invalid duration fields" do
    [ { duration_mode: nil, duration_months: nil },
      { duration_mode: "invalid", duration_months: "bad", custom_duration_weeks: -4 },
      { plan_length: "custom", custom_duration_weeks: "1.5" },
      { plan_length: "bad" } ].each do |duration|
      config = configuration(**duration)
      expect(config).to be_valid
      expect(config.ends_on).to eq(config.event_on)
      expect(Planning::PhaseAllocator.new(config).call.last.ends_on).to eq(config.event_on)
    end
  end

  it "PLN-010 enforces the event requirements and exact 28-day minimum" do
    start = Date.new(2026, 9, 7)
    expect(configuration(event_on: start + 28)).to be_valid
    expect(configuration(event_on: start + 27)).not_to be_valid
    expect(configuration(event_name: "", event_on: nil)).not_to be_valid
  end

  it "PLN-010 validates only the chosen length, using calendar months and inclusive whole weeks" do
    start = Date.new(2028, 1, 31)
    { "1" => Date.new(2028, 2, 28), "3" => Date.new(2028, 4, 29), "6" => Date.new(2028, 7, 30) }.each do |length, finish|
      config = configuration(goal: "increase_ftp", starts_on: start, plan_length: length, custom_duration_weeks: "bad")
      expect(config).to be_valid
      expect(config.ends_on).to eq(finish)
    end
    config = configuration(goal: "increase_ftp", starts_on: start, plan_length: "custom", custom_duration_weeks: "4", duration_months: "bad")
    expect(config).to be_valid
    expect(config.ends_on).to eq(start + 27)
    [ nil, "3", "4.5", "bad" ].each do |weeks|
      invalid = configuration(goal: "increase_ftp", plan_length: "custom", custom_duration_weeks: weeks)
      expect(invalid).not_to be_valid
      expect(invalid.ends_on).to be_nil
    end
    invalid = configuration(goal: "increase_ftp", plan_length: "2")
    expect(invalid).not_to be_valid
    expect(invalid.ends_on).to be_nil
  end

  it "PLN-010 preserves raw draft values independently of parsing" do
    config = configuration(plan_length: "custom", custom_duration_weeks: "2.5", event_details_open: "1")
    expect(config.custom_duration_weeks).to be_nil
    expect(config.input_value(:custom_duration_weeks)).to eq("2.5")
    expect(config.event_details_open).to be(true)
  end

  it "CYF-89 / PLN-012 ignores an inactive cycle count but validates the selected cycle" do
    [ nil, "", "0", "2.5", "invalid", "3" ].each do |count|
      continuous = configuration(progression_mode: "continuous", hard_weeks_before_recovery: count)
      expect(continuous).to be_valid
      expect(continuous.hard_weeks_before_recovery).to be_nil
      expect(continuous.input_value(:hard_weeks_before_recovery)).to eq(count)
    end

    [ nil, "", "0", "2.5", "invalid" ].each do |count|
      cycle = configuration(progression_mode: "hard_recovery_cycle", hard_weeks_before_recovery: count)
      expect(cycle).not_to be_valid
      expect(cycle.errors[:hard_weeks_before_recovery]).to include("must be a positive whole number")
      expect(cycle.input_value(:hard_weeks_before_recovery)).to eq(count)
    end
    expect(configuration(progression_mode: "hard_recovery_cycle", hard_weeks_before_recovery: "3")).to be_valid
  end
end
