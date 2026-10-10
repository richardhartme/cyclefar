require "engine_helper"
require_relative "../../app/services/workouts/directional_adjustment"

RSpec.describe Workouts::DirectionalAdjustment do
  def generate(subtype: :threshold, level: 3, duration: 60, variation: nil, load_adjustments: {})
    Workouts::Generator.new(
      subtype: subtype,
      progression_level: level,
      duration_minutes: duration,
      variation_key: variation,
      load_adjustments: load_adjustments).call
  end

  def adjust(workout, action, maximum_level: nil)
    described_class.new(
      action: action,
      steps: workout.steps,
      ftp_watts: 260,
      progression_level: workout.progression_level,
      maximum_level: maximum_level,
      tss_scale: 4,
      subtype: workout.subtype,
      duration_minutes: workout.duration_minutes,
      variation_key: workout.variation_key,
      load_adjustments: workout.load_adjustments).call
  end

  it "WKO-004 skips the load-increasing Over-Unders level 2 when making level 3 easier" do
    result = adjust(generate(subtype: :over_under), :easier)

    expect(result.definition.progression_level).to eq(1)
    expect(result.current_metrics.estimated_tss).to be_within(0.001).of(64.186)
    expect(result.metrics.estimated_tss).to be_within(0.001).of(59.377)
  end

  it "WKO-004 skips the load-decreasing Over-Unders level 3 when making level 2 harder" do
    result = adjust(generate(subtype: :over_under, level: 2, duration: 90), :harder)

    expect(result.definition.progression_level).to eq(4)
    expect(result.metrics.estimated_tss.round).to be > result.current_metrics.estimated_tss.round
  end

  [ :easier, :harder ].each do |action|
    [ :recovery, :endurance, :tempo, :sweet_spot, :threshold, :vo2_max, :over_under ].each do |subtype|
      [ 30, 45, 60, 90, 120 ].each do |duration|
        it "WKO-004 repeatedly makes #{duration}-minute #{subtype} #{action} or stops without cycling" do
          current = generate(subtype: subtype, level: action == :easier ? 7 : 1, duration: duration)
          seen = []
          stopped = false
          20.times do
            begin
              result = adjust(current, action)
            rescue described_class::LimitReached
              stopped = true
              break
            end
            comparison = action == :easier ? :< : :>
            expect(result.metrics.estimated_tss.public_send(comparison, result.current_metrics.estimated_tss)).to be(true)
            expect(result.metrics.estimated_tss.round.public_send(comparison, result.current_metrics.estimated_tss.round)).to be(true)
            expect(result.definition.subtype).to eq(subtype.to_s)
            expect(result.definition.steps.sum(&:duration_seconds)).to eq(duration * 60)
            expect(result.definition.steps.map(&:duration_seconds)).to all(be >= 30)
            expect(result.definition.steps.map(&:target_high_pct_ftp)).to all(be <= 120)
            expect(seen).not_to include(result.definition.steps)
            seen << result.definition.steps
            current = result.definition
          end
          expect(stopped).to be(true), "Directional adjustments must reach a finite limit"
        end
      end
    end
  end

  it "WKO-004 ignores changes hidden by whole-number TSS rounding" do
    current = generate(level: 2)
    expect { adjust(current, :easier) }.to raise_error(described_class::LimitReached, /No lower-load option/)
    expect { adjust(generate(subtype: :recovery), :harder) }.to raise_error(described_class::LimitReached, /No higher-load option/)
  end

  it "WKO-004 accounts for decimal persistence when rounding near a display boundary" do
    target = Math.sqrt(44.49999 / 100) * 100
    step = Workouts::StepDefinition.new(
      kind: "steady",
      label: "Endurance",
      duration_seconds: 3600,
      target_low_pct_ftp: target,
      target_high_pct_ftp: target,
      group_key: "main")
    current = generate(subtype: :endurance).with(steps: [ step ])
    # Persistence rounds this canonical load to 44.5000, displayed as 45.
    # Alternating's 44.943 TSS must not qualify as a displayed increase.
    expect { adjust(current, :harder) }.to raise_error(described_class::LimitReached)
  end

  it "WKO-004 chooses endurance profiles by load and stops instead of wrapping" do
    current = generate(subtype: :endurance, variation: "alternating")
    easier = adjust(current, :easier)
    expect(easier.definition.variation_key).to eq("sustained")
    expect(easier.definition.progression_level).to be_nil
    expect { adjust(easier.definition, :easier) }.to raise_error(described_class::LimitReached)
    harder = adjust(easier.definition, :harder)
    expect(harder.definition.variation_key).to eq("alternating")
    expect { adjust(harder.definition, :harder) }.to raise_error(described_class::LimitReached)
  end

  it "WKO-004 retains the shortened main set when higher requested levels cannot fit" do
    current = generate(subtype: :sweet_spot, duration: 30, level: 1)
    expect(current.reason_codes).to include("short_main_set", "compressed_warm_up")
    expect { adjust(current, :harder) }.to raise_error(described_class::LimitReached)
  end

  it "WKO-004 applies saved power and progression ceilings to every candidate" do
    current = generate(subtype: :tempo, level: 1, duration: 90, load_adjustments: { "return_target_band" => [ 55, 68 ] })
    result = adjust(current, :harder, maximum_level: 2)
    expect(result.definition.progression_level).to eq(2)
    expect(result.definition.load_adjustments).to eq(current.load_adjustments)
    expect(result.definition.steps.map(&:target_high_pct_ftp)).to all(be <= 68)
    expect(result.definition.steps.filter_map(&:end_target_high_pct_ftp)).to all(be <= 68)
    expect { adjust(result.definition, :harder, maximum_level: 2) }.to raise_error(described_class::LimitReached)
  end

  it "WKO-004 preserves taper work factors and lowered targets" do
    adjustments = { "main_set_factor" => 0.6, "lower_targets" => true }
    current = generate(subtype: :sweet_spot, level: 4, load_adjustments: adjustments)
    result = adjust(current, :easier)
    expect(result.definition.load_adjustments).to eq(adjustments)
    main = result.definition.steps.select { |step| step.group_key == "main" }
    expect(main.sum(&:duration_seconds)).to be < current.steps.select { |step| step.group_key == "main" }.sum(&:duration_seconds)
    expect(main.map { |step| [ step.target_low_pct_ftp, step.target_high_pct_ftp ] }.uniq).to eq([ [ 88, 88 ] ])
  end

  it "WKO-004 preserves easy-filler reductions instead of rebuilding a full main set" do
    current = generate(subtype: :sweet_spot, level: 1, duration: 90, load_adjustments: { "easy_filler" => true })
    expect { adjust(current, :harder) }.to raise_error(described_class::LimitReached)
  end

  it "WKO-004 selects the same canonical replacement for identical inputs" do
    current = generate(subtype: :over_under, variation: "redistributed_recovery")
    first = adjust(current, :easier)
    expect(first.definition.variation_key).to eq("redistributed_recovery")
    expect(adjust(current, :easier)).to eq(first)
  end
end
