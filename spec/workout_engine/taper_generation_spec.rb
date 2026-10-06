require "engine_helper"

RSpec.describe "PLN-022 tapered canonical main sets" do
  Training::Rules::LADDERS.keys.product([ 0.60, 0.75 ]).each do |subtype, factor|
    it "reduces #{subtype} hard time by #{factor} while retaining bands, positive steps and exact duration" do
      normal = Workouts::Generator.new(subtype: subtype, duration_minutes: 120, progression_level: 4).call
      tapered = Workouts::Generator.new(
        subtype: subtype,
        duration_minutes: 120,
        progression_level: 4,
        load_adjustments: { "main_set_factor" => factor }).call
      work = tapered.steps.select { |step| step.group_key == "main" }
      normal_work = normal.steps.select { |step| step.group_key == "main" }
      expect(work.map { |step| [ step.target_low_pct_ftp, step.target_high_pct_ftp ] }).to eq(normal_work.map { |step| [ step.target_low_pct_ftp, step.target_high_pct_ftp ] })
      expect(work.sum(&:duration_seconds).to_f / normal_work.sum(&:duration_seconds)).to be_within(0.08).of(factor)
      expect(tapered.steps.sum(&:duration_seconds)).to eq(120 * 60)
      expect(tapered.steps.map(&:duration_seconds)).to all(be > 0)
      expect(tapered.steps.map(&:position)).to eq((1..tapered.steps.length).to_a)
      expect(tapered.name).to include("tapered")
      expect(tapered.load_adjustments).to eq("main_set_factor" => factor)
    end
  end

  [ 0, -0.2, 1.1 ].each do |factor|
    it "rejects invalid taper factor #{factor}" do
      expect { Workouts::Generator.new(subtype: :threshold, duration_minutes: 60, load_adjustments: { "main_set_factor" => factor }).call }.to raise_error(ArgumentError)
    end
  end
end
