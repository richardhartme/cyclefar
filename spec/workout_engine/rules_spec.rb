require "engine_helper"

RSpec.describe "V1 workout prescriptions" do
  # Independent fixtures transcribed from TRAINING_ENGINE.md section 14.
  {
    tempo: [ [ 2, 10, 4 ], [ 2, 15, 4 ], [ 3, 12, 4 ], [ 2, 20, 5 ], [ 3, 15, 4 ], [ 2, 25, 5 ], [ 3, 20, 5 ] ],
    sweet_spot: [ [ 3, 8, 4 ], [ 3, 10, 4 ], [ 3, 12, 4 ], [ 2, 20, 5 ], [ 3, 15, 5 ], [ 2, 25, 5 ], [ 3, 20, 5 ] ],
    threshold: [ [ 4, 6, 4 ], [ 3, 8, 4 ], [ 4, 8, 4 ], [ 3, 10, 5 ], [ 3, 12, 5 ], [ 2, 20, 6 ], [ 3, 15, 5 ] ],
    vo2_max: [ [ 5, 2, 3 ], [ 6, 2, 3 ], [ 5, 3, 3 ], [ 6, 3, 3 ], [ 5, 4, 4 ], [ 4, 5, 5 ], [ 5, 5, 5 ] ],
    over_under: [ [ 2, 9, 5 ], [ 3, 9, 5 ], [ 2, 12, 5 ], [ 3, 12, 5 ], [ 2, 16, 6 ], [ 3, 15, 6 ], [ 2, 20, 7 ] ]
  }.each do |subtype, ladder|
    ladder.each_with_index do |(repetitions, minutes, recovery), index|
      it "preserves the specified #{subtype} level #{index + 1} main set when it fits" do
        workout = Workouts::Generator.new(subtype: subtype, progression_level: index + 1, duration_minutes: 120).call
        main = workout.steps.select { |step| step.group_key == "main" }
        blocks = main.group_by(&:group_iteration)
        expect(blocks.keys).to eq((1..repetitions).to_a)
        expect(blocks.values.map { |steps| steps.sum(&:duration_seconds) }).to eq([ minutes * 60 ] * repetitions)
        expect(workout.steps.select { |step| step.group_key == "recovery" }.map(&:duration_seconds)).to eq([ recovery * 60 ] * (repetitions - 1))
        expect(workout.progression_level).to eq(index + 1)
        expect(workout.reason_codes).not_to include("duration_level_reduced", "short_main_set", "compressed_warm_up")
      end
    end
  end

  %i[recovery endurance tempo sweet_spot threshold vo2_max over_under].each do |subtype|
    it "keeps all #{subtype} work within its prescribed power band at every level and fit" do
      (1..7).to_a.product([ 30, 45, 60, 75, 90, 120 ], Workouts::Variations.keys_for(subtype)).each do |level, duration, key|
        workout = Workouts::Generator.new(subtype: subtype, progression_level: level, duration_minutes: duration, variation_key: key).call
        main = workout.steps.select { |step| step.group_key == "main" }
        main.each do |step|
          band = case subtype
          when :recovery then [ 45, 55 ]
          when :endurance then [ 60, 75 ]
          when :tempo then [ 78, 87 ]
          when :sweet_spot then [ 88, 94 ]
          when :threshold then workout.progression_level >= 5 ? [ 95, 100 ] : [ 95, 102 ]
          when :vo2_max then { 120 => [ 112, 118 ], 180 => [ 110, 116 ], 240 => [ 108, 114 ], 300 => [ 106, 112 ] }.fetch(step.duration_seconds)
          when :over_under then step.label == "Under" ? [ 88, 94 ] : [ 102, 108 ]
          end
          expect(step.target_low_pct_ftp).to be >= band[0]
          expect(step.target_high_pct_ftp).to be <= band[1]
          if step.kind == "ramp"
            expect(step.end_target_low_pct_ftp).to be >= band[0]
            expect(step.end_target_high_pct_ftp).to be <= band[1]
          end
        end
        if %i[recovery endurance].include?(subtype)
          ceiling = subtype == :recovery ? 55 : 75
          expect(workout.steps.map(&:target_high_pct_ftp)).to all(be <= ceiling)
          expect(workout.steps.filter_map(&:end_target_high_pct_ftp)).to all(be <= ceiling)
        end
      end
    end
  end

  it "stores the five zones separately from the overlapping Sweet Spot band" do
    expect(Training::V1::Rules::ZONES).to eq(recovery: 0..55, endurance: 56..75, tempo: 76..90, threshold: 91..105, vo2_max: 106..120)
    expect(Training::V1::Rules::TARGETS[:sweet_spot]).to eq([ 88, 94 ])
    expect { Training::V1::Rules::LADDERS[:threshold][0][0] = 99 }.to raise_error(FrozenError)
    expect { Training::V1::Rules::WARM_UPS[:threshold][:start][0] = 100 }.to raise_error(FrozenError)
  end

  it "keeps requested phase, goal and discipline as explicit context" do
    workout = Workouts::Generator.new(
      subtype: :vo2_max,
      duration_minutes: 60,
      phase: :speciality,
      goal: :event,
      discipline: :mtb).call
    expect(workout).to have_attributes(phase: "speciality", goal: "event", discipline: "mtb")
    expect(workout.purpose).to include("Speciality phase", "aerobic-power")
  end
end
