require "engine_helper"

RSpec.describe "Endurance profiles" do
  [ 30, 31, 45, 60, 90, 120, 240 ].each do |duration|
    it "fits three distinct endurance profiles into #{duration} minutes with comparable load" do
      workouts = %w[a b c].map do |key|
        Workouts::Generator.new(subtype: :endurance, duration_minutes: duration, variation_key: key).call
      end
      main_sets = workouts.map { |workout| workout.steps.select { |step| step.group_key == "main" } }
      expect(main_sets[0].size).to eq(1)
      expect(main_sets[1].map(&:kind).uniq).to eq([ "steady" ])
      expect(main_sets[1].map(&:target_low_pct_ftp).uniq.size).to eq(2)
      expect(main_sets[2].map(&:kind).uniq).to eq([ "ramp" ])
      main_sets[2].each_cons(2) do |first, second|
        expect(first.end_target_low_pct_ftp).to eq(second.target_low_pct_ftp)
        expect(first.end_target_high_pct_ftp).to eq(second.target_high_pct_ftp)
      end
      workouts.each do |workout|
        expect(workout.steps.sum(&:duration_seconds)).to eq(duration * 60)
        expect(workout.steps).to all(satisfy { |step| step.duration_seconds >= 30 && step.duration_seconds % 30 == 0 })
      end
      main_sets.flatten.each do |step|
        targets = [ step.target_low_pct_ftp, step.target_high_pct_ftp, step.end_target_low_pct_ftp, step.end_target_high_pct_ftp ].compact
        expect(targets).to all(be_between(60, 75))
      end
      metrics = workouts.map { |workout| Metrics::WorkoutCalculator.new(steps: workout.steps, ftp_watts: 260).call }
      metrics.permutation(2).each do |before, after|
        expect((after.estimated_tss / before.estimated_tss - 1).abs).to be <= 0.05
      end
    end
  end

  it "cycles all endurance profiles for an explicit Same shuffle" do
    expect(Workouts::Variations.next_key("a", subtype: :endurance)).to eq("b")
    expect(Workouts::Variations.next_key("b", subtype: :endurance)).to eq("c")
    expect(Workouts::Variations.next_key("c", subtype: :endurance)).to eq("a")
  end
end
