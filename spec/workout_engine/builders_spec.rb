require "engine_helper"

RSpec.describe "Warm-up, cool-down and exact-duration fitting" do
  {
    tempo: [ 480, 2, 90, 100, 120 ], sweet_spot: [ 480, 2, 90, 100, 120 ],
    threshold: [ 600, 2, 95, 105, 180 ], vo2_max: [ 600, 3, 105, 115, 180 ],
    over_under: [ 600, 3, 105, 115, 180 ]
  }.each do |subtype, (ramp, primers, low, high, settle)|
    it "builds the preferred #{subtype} ramp, preparation efforts and easy settling period" do
      steps = Workouts::WarmUpBuilder.new(subtype: subtype).call
      expect(steps.first).to have_attributes(kind: "ramp", duration_seconds: ramp, target_low_pct_ftp: 45, target_high_pct_ftp: 55)
      efforts = steps.select { |step| step.label == "Preparation effort" }
      expect(efforts.length).to eq(primers)
      expect(efforts).to all(have_attributes(duration_seconds: 30, target_low_pct_ftp: low, target_high_pct_ftp: high))
      expect(steps.last).to have_attributes(duration_seconds: settle, target_low_pct_ftp: 50, target_high_pct_ftp: 60)
      compact = Workouts::WarmUpBuilder.new(subtype: subtype, compact: true).call
      expect(compact.length).to eq(1)
      expect(compact.first).to have_attributes(kind: "ramp", duration_seconds: 300)
    end
  end

  it "keeps easy warm-ups simple and within their target ceiling" do
    recovery = Workouts::WarmUpBuilder.new(subtype: :recovery).call
    endurance = Workouts::WarmUpBuilder.new(subtype: :endurance).call
    expect(recovery.length).to eq(1)
    expect(recovery.first).to have_attributes(duration_seconds: 300, end_target_high_pct_ftp: 55)
    expect(endurance.length).to eq(1)
    expect(endurance.first).to have_attributes(duration_seconds: 480, end_target_high_pct_ftp: 70)
  end

  it "uses five-minute cool-downs and eight minutes for long sessions" do
    short = Workouts::CoolDownBuilder.new(subtype: :threshold, duration_minutes: 60).call.fetch(0)
    long = Workouts::CoolDownBuilder.new(subtype: :threshold, duration_minutes: 120).call.fetch(0)
    expect(short).to have_attributes(duration_seconds: 300, target_low_pct_ftp: 55, target_high_pct_ftp: 60,
      end_target_low_pct_ftp: 40, end_target_high_pct_ftp: 50)
    expect(long.duration_seconds).to eq(480)
  end

  it "compresses preparation before reducing the prescribed main-set level" do
    fit = Workouts::ExactDurationFitter.new(subtype: :threshold, duration_minutes: 75, progression_level: 7, variation_key: "a").call
    expect(fit.progression_level).to eq(7)
    expect(fit.compressed).to be(true)
    expect(fit.name_suffix).to eq("3x15")
    expect(fit.steps.sum(&:duration_seconds)).to eq(4500)
  end

  it "steps down the ladder before using a short fallback and records the effective level" do
    fit = Workouts::ExactDurationFitter.new(subtype: :threshold, duration_minutes: 60, progression_level: 7, variation_key: "a").call
    expect(fit.progression_level).to eq(6)
    expect(fit.shortened).to be(false)
    expect(fit.name_suffix).to eq("2x20")
  end
end
