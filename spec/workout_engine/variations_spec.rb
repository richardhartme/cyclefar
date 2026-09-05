require "engine_helper"

RSpec.describe "Deterministic workout variations" do
  %i[recovery endurance tempo sweet_spot threshold vo2_max over_under].product((1..7).to_a, [ 30, 45, 60, 75, 90, 120 ]).each do |subtype, level, duration|
    it "WKO-004 preserves intent and load for #{subtype} level #{level}, #{duration} min" do
      variants = %w[a b].map do |key|
        Workouts::Generator.new(subtype: subtype, progression_level: level, duration_minutes: duration, variation_key: key).call
      end
      first, second = variants
      expect(first.steps.map { |step| step.to_h.except(:label, :group_key, :group_iteration) }).not_to eq(
        second.steps.map { |step| step.to_h.except(:label, :group_key, :group_iteration) }
      )
      expect(first.progression_level).to eq(second.progression_level)
      metrics = variants.map { |workout| Metrics::WorkoutCalculator.new(steps: workout.steps, ftp_watts: 260).call }
      expect((metrics[0].estimated_if - metrics[1].estimated_if).abs).to be <= 0.03
      # Both directions matter because the deterministic cycle wraps b -> a.
      metrics.permutation.each do |before, after|
        expect((after.estimated_tss / before.estimated_tss - 1).abs).to be <= 0.05
      end
    end
  end

  it "rotates explicit variation keys without randomness" do
    expect(Workouts::Variations.next_key("a")).to eq("b")
    expect(Workouts::Variations.next_key("b")).to eq("a")
    expect { Workouts::Variations.next_key("unknown") }.to raise_error(ArgumentError)
  end
end
