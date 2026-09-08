require "engine_helper"

RSpec.describe Workouts::Generator do
  subtypes = %i[recovery endurance tempo sweet_spot threshold vo2_max over_under]
  durations = [ 30, 45, 60, 75, 90, 120 ]

  subtypes.product((1..7).to_a, durations, %w[a b]).each do |subtype, level, duration, variation|
    it "GEN-001 generates exact #{duration} min #{subtype} level #{level} variation #{variation}" do
      workout = described_class.new(
        subtype: subtype,
        duration_minutes: duration,
        progression_level: level,
        variation_key: variation).call
      expect(workout.steps.sum(&:duration_seconds)).to eq(duration * 60)
      expect(workout.steps.map(&:position)).to eq((1..workout.steps.length).to_a)
      if %i[recovery endurance].include?(subtype)
        expect(workout.progression_level).to be_nil
      else
        expect(workout.progression_level).to be_between(1, level)
      end
      expect(workout.subtype).to eq(subtype.to_s)
      expect(workout.engine_version).to eq("v1")
      expect(workout.steps.first.group_key).to eq("warm_up")
      expect(workout.steps.last.group_key).to eq("cool_down")
      expect(workout.steps.first.duration_seconds).to be >= (subtype == :endurance ? 480 : 300)
      expect(workout.steps.last.duration_seconds).to be >= 300
      workout.steps.each do |step|
        expect(step.duration_seconds).to be >= 30
        expect(step.duration_seconds % 30).to eq(0)
        expect(step.target_low_pct_ftp).to be > 0
        expect(step.target_high_pct_ftp).to be_between(step.target_low_pct_ftp, 120)
        if step.kind == "ramp"
          expect(step.end_target_high_pct_ftp).to be_between(step.end_target_low_pct_ftp, 120)
        end
      end
    end
  end

  it "WKO-002 generates the reviewable 60-minute Threshold 3x12 example" do
    workout = described_class.new(subtype: :threshold, duration_minutes: 60, progression_level: 5, phase: :build).call
    expect(workout.name).to eq("Threshold 3x12")
    expect(workout.main_set_summary).to include("3 x 12 min", "5 min recovery")
    expect(workout.purpose).to include("Build", "sustained")
    main = workout.steps.select { |step| step.group_key == "main" }
    expect(main.map(&:duration_seconds)).to eq([ 720, 720, 720 ])
    expect(main.map { |step| [ step.target_low_pct_ftp, step.target_high_pct_ftp ] }.uniq).to eq([ [ 95, 100 ] ])
  end

  subtypes.each do |subtype|
    it "handles short fits and non-quarter-hour durations for #{subtype}" do
      [ 31, 32, 44, 47, 59, 61, 181, 600 ].each do |duration|
        workout = described_class.new(subtype: subtype, duration_minutes: duration, progression_level: 7).call
        expect(workout.steps.sum(&:duration_seconds)).to eq(duration * 60)
        expect(workout.steps.map(&:duration_seconds).min).to be >= 30
      end
    end
  end

  it "records duration-driven level reductions and short main-set fallback" do
    workout = described_class.new(subtype: :sweet_spot, duration_minutes: 30, progression_level: 7).call
    expect(workout.progression_level).to eq(1)
    expect(workout.requested_progression_level).to eq(7)
    expect(workout.reason_codes).to include("duration_level_reduced", "short_main_set", "compressed_warm_up")
    expect(workout.name).to eq("Sweet Spot 2x8")
  end

  it "adds only easy filler when extra time remains" do
    short = described_class.new(subtype: :threshold, duration_minutes: 90, progression_level: 5).call
    long = described_class.new(subtype: :threshold, duration_minutes: 180, progression_level: 5).call
    main = ->(workout) { workout.steps.select { |step| step.group_key == "main" }.map(&:duration_seconds) }
    expect(main.call(long)).to eq(main.call(short))
    expect(long.steps.select { |step| step.group_key == "filler" }.map(&:target_high_pct_ftp)).to all(be <= 75)
  end

  it "is repeatable and returns deeply immutable values" do
    generator = described_class.new(subtype: :over_under, duration_minutes: 60, progression_level: 3)
    original = generator.call
    expect(generator.call).to eq(original)
    expect { original.steps << original.steps.first }.to raise_error(FrozenError)
    expect { original.steps.first.label.replace("mutated") }.to raise_error(FrozenError)
    expect { original.reason_codes << "changed" }.to raise_error(FrozenError)
    expect { original.name.replace("changed") }.to raise_error(FrozenError)
  end

  [ { subtype: :intervals }, { subtype: :ftp_test }, { duration_minutes: 29 },
    { duration_minutes: 60.5 }, { duration_minutes: "60" }, { duration_minutes: nil },
    { progression_level: 0 }, { progression_level: 8 }, { progression_level: 1.5 },
    { variation_key: "unknown" }, { phase: :unknown }, { goal: :unknown }, { discipline: :unknown } ].each do |invalid|
    it "rejects invalid generator input #{invalid.inspect}" do
      expect { described_class.new(**{ subtype: :threshold, duration_minutes: 60 }.merge(invalid)).call }.to raise_error(ArgumentError)
    end
  end
end
