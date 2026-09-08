require_relative "warm_up_builder"
require_relative "cool_down_builder"
require_relative "main_set_builder"
require_relative "aerobic_set_builder"

module Workouts
  class ExactDurationFitter
    Result = Data.define(:steps, :progression_level, :name_suffix, :summary, :shortened, :compressed)

    def initialize(subtype:, duration_minutes:, progression_level:, variation_key:)
      @subtype = subtype.to_sym
      @duration_minutes = duration_minutes
      @level = progression_level
      @variation_key = variation_key
    end

    def call
      return fit_aerobic unless Training::V1::Rules::LADDERS.key?(@subtype)

      @level.downto(1) do |level|
        main = MainSetBuilder.new(subtype: @subtype, progression_level: level, variation_key: @variation_key).call
        result = fit_main(main)
        return result if result
      end
      main = MainSetBuilder.new(subtype: @subtype, progression_level: 1, variation_key: @variation_key, shortened: true).call
      fit_main(main) || raise(ArgumentError, "No valid main set fits the requested duration")
    end

    private

    def fit_main(main)
      [ false, true ].each do |compact|
        warm = WarmUpBuilder.new(subtype: @subtype, compact: compact).call
        cool = CoolDownBuilder.new(subtype: @subtype, duration_minutes: @duration_minutes, compact: compact).call
        remaining = @duration_minutes * 60 - (warm + main.steps + cool).sum(&:duration_seconds)
        next if remaining.negative?

        # Whole-minute requests and 30-second components cannot leave junk steps.
        filler = remaining.zero? ? [] : [ easy_filler(remaining) ]
        return Result.new(
          steps: positioned(warm + main.steps + filler + cool),
          progression_level: main.progression_level,
          name_suffix: main.name_suffix,
          summary: main.summary,
          shortened: main.shortened,
          compressed: compact)
      end
      nil
    end

    def fit_aerobic
      warm = WarmUpBuilder.new(subtype: @subtype).call
      cool = CoolDownBuilder.new(subtype: @subtype, duration_minutes: @duration_minutes).call
      remaining = @duration_minutes * 60 - (warm + cool).sum(&:duration_seconds)
      main = AerobicSetBuilder.new(subtype: @subtype, duration_seconds: remaining, variation_key: @variation_key).call
      Result.new(
        steps: positioned(warm + main + cool),
        progression_level: nil,
        name_suffix: "#{@duration_minutes} min".freeze,
        summary: aerobic_summary.freeze,
        shortened: false,
        compressed: false)
    end

    def positioned(steps)
      steps.each_with_index.map { |step, index| step.with(position: index + 1) }.freeze
    end

    def easy_filler(seconds)
      target = Training::V1::Rules::TARGETS[:easy]
      StepDefinition.new(
        kind: "steady",
        label: "Easy aerobic riding",
        duration_seconds: seconds,
        target_low_pct_ftp: target[0],
        target_high_pct_ftp: target[1],
        group_key: "filler")
    end

    def aerobic_summary
      rules = Training::V1::Rules
      if @subtype == :recovery
        band = rules::TARGETS[:recovery].join("–")
        @variation_key == "a" ? "Easy steady riding at #{band}% FTP" : "Gentle recovery ramp within #{band}% FTP"
      else
        band = rules::ENDURANCE_STEADY_TARGET.join("–")
        rest = rules::ENDURANCE_BREAK_SECONDS / 60
        @variation_key == "a" ? "Steady endurance at #{band}% FTP" : "Two endurance blocks at #{band}% FTP with #{rest} min easy between"
      end
    end
  end
end
