require_relative "warm_up_builder"
require_relative "cool_down_builder"
require_relative "main_set_builder"
require_relative "aerobic_set_builder"

module Workouts
  # Fits workout steps to exact duration by adjusting progression and fill.
  class ExactDurationFitter
    Result = Data.define(:steps, :progression_level, :name_suffix, :summary, :shortened, :compressed)

    def initialize(subtype:, duration_minutes:, progression_level:, variation_key:, easy_filler: false, work_factor: 1.0)
      @subtype = subtype.to_sym
      @duration_minutes = duration_minutes
      @level = progression_level
      @variation_key = variation_key
      @easy_filler = easy_filler
      @work_factor = Float(work_factor)
      raise ArgumentError, "work_factor must be between zero and one" unless @work_factor > 0 && @work_factor <= 1
    end

    def call
      return fit_aerobic unless Training::Rules::LADDERS.key?(@subtype)
      if @easy_filler
        main = MainSetBuilder.new(subtype: @subtype, progression_level: 1, variation_key: @variation_key, shortened: true, work_factor: @work_factor).call
        return fit_main(main) || raise(ArgumentError, "No valid main set fits the requested duration")
      end

      @level.downto(1) do |level|
        main = MainSetBuilder.new(subtype: @subtype, progression_level: level, variation_key: @variation_key, work_factor: @work_factor).call
        result = fit_main(main)
        return result if result
      end
      main = MainSetBuilder.new(subtype: @subtype, progression_level: 1, variation_key: @variation_key, shortened: true, work_factor: @work_factor).call
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
      target = Training::Rules::TARGETS[:easy]
      StepDefinition.new(
        kind: "steady",
        label: "Easy aerobic riding",
        duration_seconds: seconds,
        target_low_pct_ftp: target[0],
        target_high_pct_ftp: target[1],
        group_key: "filler")
    end

    def aerobic_summary
      rules = Training::Rules
      if @subtype == :recovery
        band = rules::TARGETS[:recovery].join("–")
        @variation_key == "steady" ? "Easy steady riding at #{band}% FTP" : "Gentle recovery ramp within #{band}% FTP"
      else
        band = rules::ENDURANCE_STEADY_TARGET.join("–")
        case @variation_key
        when "sustained" then "Steady endurance at #{band}% FTP"
        when "alternating" then "Alternating low/high endurance at #{rules::ENDURANCE_LOW_TARGET.join('–')} / #{rules::ENDURANCE_HIGH_TARGET.join('–')}% FTP"
        when "undulating" then "Undulating endurance between #{rules::ENDURANCE_LOW_TARGET.join('–')} and #{rules::ENDURANCE_HIGH_TARGET.join('–')}% FTP"
        end
      end
    end
  end
end
