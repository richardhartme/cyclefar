require "engine_helper"

RSpec.describe Planning::WeeklyLoadCap do
  Candidate = Data.define(:scheduled_on, :definition, :intent, :estimated_tss, :adjustable) do
    def adjustable? = adjustable
  end

  def definition(**attributes)
    Workouts::Generator.new(
      subtype: :threshold,
      duration_minutes: 90,
      progression_level: 1,
      phase: :build,
      goal: :increase_ftp,
**attributes).call
  end

  def candidate(workout, intent: workout.subtype, date: Date.new(2026, 10, 5), adjustable: true)
    metrics = Metrics::WorkoutCalculator.new(steps: workout.steps, ftp_watts: 260).call
    Candidate.new(scheduled_on: date, definition: workout, intent: intent, estimated_tss: metrics.estimated_tss, adjustable: adjustable)
  end

  def reduce(items, limit:)
    described_class.reduce(items, limit: limit) do |item, stage|
      Planning::LoadReduction.options(item.definition, stage: stage, intent: item.intent).map do |option|
        candidate(option, intent: item.intent, date: item.scheduled_on)
      end
    end
  end

  def between(first, second)
    (candidate(first).estimated_tss + candidate(second).estimated_tss) / 2
  end

  it "LOAD-002 lowers the highest-load interval first and stops before later fallbacks when feasible" do
    lower = candidate(definition(progression_level: 3))
    higher = candidate(definition(progression_level: 7), date: lower.scheduled_on + 1)
    result = reduce([ lower, higher ], limit: lower.estimated_tss + higher.estimated_tss - 1)
    expect(result.first).to eq(lower)
    expect(result.last.definition.progression_level).to be < higher.definition.progression_level
    expect(result.last.definition.load_adjustments).to be_empty
    expect(result.sum(&:estimated_tss)).to be <= lower.estimated_tss + higher.estimated_tss - 1
  end

  it "LOAD-002 tries a lower-load valid variation before changing targets" do
    original = definition(subtype: :recovery, variation_key: "gentle_ramp")
    steady = definition(subtype: :recovery, variation_key: "steady")
    result = reduce([ candidate(original) ], limit: between(original, steady)).sole
    expect(result.definition.variation_key).to eq("steady")
    expect(result.definition.load_adjustments).to be_empty
  end

  it "LOAD-002 lowers the main-set target within its allowed band before changing subtype or structure" do
    original = definition
    lowered = definition(load_adjustments: { "lower_targets" => true })
    result = reduce([ candidate(original, intent: "intervals") ], limit: between(original, lowered)).sole
    expect(result.definition.subtype).to eq("threshold")
    expect(result.definition.load_adjustments).to eq("lower_targets" => true)
    expect(result.definition.steps.map(&:duration_seconds)).to eq(original.steps.map(&:duration_seconds))
    result.definition.steps.zip(original.steps).each do |after, before|
      expect(after.target_low_pct_ftp).to eq(before.target_low_pct_ftp)
      expect(after.target_high_pct_ftp).to be_between(before.target_low_pct_ftp, before.target_high_pct_ftp)
    end
  end

  it "LOAD-002 substitutes only broad Intervals with a goal/phase-compatible less demanding subtype" do
    original = definition(load_adjustments: { "lower_targets" => true })
    sweet_spot = definition(subtype: :sweet_spot, load_adjustments: { "lower_targets" => true })
    result = reduce([ candidate(original, intent: "intervals") ], limit: between(original, sweet_spot)).sole
    expect(result.definition.subtype).to eq("sweet_spot")
    expect(result.definition.duration_minutes).to eq(90)
    expect(result.definition.load_adjustments).not_to have_key("easy_filler")
    base_vo2 = definition(subtype: :vo2_max, phase: :base)
    options = Planning::LoadReduction.options(base_vo2, stage: :subtype, intent: "intervals")
    expect(options.map(&:subtype).uniq).to eq(%w[threshold sweet_spot])
    expect(Planning::LoadReduction.options(original, stage: :subtype, intent: "threshold")).to be_empty
  end

  it "LOAD-002 retains specific subtype and normal duration by using a valid short main set plus easy filler" do
    original = definition(load_adjustments: { "lower_targets" => true })
    minimum = definition(load_adjustments: { "lower_targets" => true, "easy_filler" => true })
    result = reduce([ candidate(original) ], limit: between(original, minimum)).sole
    expect(result.definition.subtype).to eq("threshold")
    expect(result.definition.load_adjustments).to include("easy_filler" => true)
    expect(result.definition.steps.sum(&:duration_seconds)).to eq(90 * 60)
    main = result.definition.steps.select { |step| step.group_key == "main" }
    expect(main.sum(&:duration_seconds)).to eq(12 * 60)
    expect(result.definition.steps.select { |step| step.group_key == "filler" }.sum(&:duration_seconds)).to be > 0
  end

  it "LOAD-002 exhausts valid options without shortening or raising load when the schedule is infeasible" do
    original = candidate(definition(progression_level: 7))
    result = reduce([ original ], limit: 1).sole
    minimum = candidate(definition(load_adjustments: { "lower_targets" => true, "easy_filler" => true }))
    expect(result.estimated_tss).to eq(minimum.estimated_tss)
    expect(result.definition.progression_level).to eq(1)
    expect(result.definition.duration_minutes).to eq(90)
    expect(result.estimated_tss).to be > 1
    expect(reduce([ original.with(adjustable: false) ], limit: 1)).to eq([ original.with(adjustable: false) ])
  end

  %w[sustained alternating undulating].each do |profile|
    it "WKO-009 keeps the #{profile} endurance profile even when its minimum load exceeds the cap" do
      original = definition(subtype: :endurance, variation_key: profile)
      result = reduce([ candidate(original) ], limit: 1).sole
      expect(result.definition.variation_key).to eq(profile)
      expect(result.definition.subtype).to eq("endurance")
      expect(result.definition.load_adjustments).to eq("lower_targets" => true)
      expect(result.definition.steps.sum(&:duration_seconds)).to eq(90 * 60)
      expect(result.definition.steps.map(&:kind)).to eq(original.steps.map(&:kind))
    end
  end
end
