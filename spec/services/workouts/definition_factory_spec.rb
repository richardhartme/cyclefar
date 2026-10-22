require "rails_helper"

RSpec.describe Workouts::DefinitionFactory, type: :service do
  let(:plan) { create(:training_plan, goal: "general_fitness", discipline: "road") }
  let(:factory) { described_class.for(plan) }

  it "builds a regular definition from a subtype and plan context" do
    definition = factory.build(kind: :workout, subtype: :threshold, duration_minutes: 60, phase: :build, progression_level: 2)

    expect(definition).to have_attributes(subtype: "threshold", duration_minutes: 60, phase: "build", discipline: "road")
    expect(definition.steps.sum(&:duration_seconds)).to eq(3600)
  end

  it "builds an opener definition when the kind is opener" do
    definition = factory.build(kind: :opener, duration_minutes: 45, phase: :taper)

    expect(definition).to have_attributes(name: "Event Opener", duration_minutes: 45, progression_level: nil)
  end

  it "rebuilds a stored workout's definition, honouring its saved load adjustments" do
    workout = create(:planned_workout, training_plan: plan, subtype: :tempo, intent: :tempo, progression_level: 2,
      generation_context: { "load_adjustments" => { "easy_filler" => true } })

    definition = factory.for_workout(workout)

    expect(definition).to have_attributes(subtype: "tempo", duration_minutes: 60, load_adjustments: { "easy_filler" => true })
    expect(factory.for_workout(workout, load_adjustments: {}).load_adjustments).to eq({})
  end

  it "rebuilds an opener workout as an opener" do
    workout = create(:planned_workout, training_plan: plan, kind: :opener, intent: :intervals, duration_minutes: 40)

    expect(factory.for_workout(workout).name).to eq("Event Opener")
  end
end
