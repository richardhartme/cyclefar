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

  it "CYF-85 defaults a missing event discipline to plan discipline but rejects an explicit invalid choice" do
    expect(configuration(discipline: "gravel", event_discipline: nil).training_discipline).to eq("gravel")
    invalid = configuration(event_discipline: "unknown")
    expect(invalid).not_to be_valid
    expect(invalid.errors[:event_discipline]).to include("is invalid")
    expect(configuration(discipline: nil, event_discipline: nil)).not_to be_valid
  end

  it "CYF-85 keeps non-event discipline authoritative and validated for non-event goals" do
    config = configuration(goal: "increase_ftp")
    expect(config).to be_valid
    expect(config.training_discipline).to eq("road")
    expect(configuration(goal: "increase_ftp", discipline: "unknown")).not_to be_valid
  end
end
