require_relative "../training/v1/rules"
require_relative "step_definition"

module Workouts
  class AerobicSetBuilder
    def initialize(subtype:, duration_seconds:, variation_key:)
      @subtype = subtype.to_sym
      @duration = duration_seconds
      @variation_key = variation_key
    end

    def call
      rules = Training::V1::Rules
      if @subtype == :recovery
        if @variation_key == "a"
          [ steady(@duration, rules::TARGETS[:recovery]) ].freeze
        else
          [ StepDefinition.new(
            kind: "ramp",
            label: "Gentle recovery progression",
            duration_seconds: @duration,
            target_low_pct_ftp: rules::RECOVERY_RAMP_START[0],
            target_high_pct_ftp: rules::RECOVERY_RAMP_START[1],
            end_target_low_pct_ftp: rules::RECOVERY_RAMP_END[0],
            end_target_high_pct_ftp: rules::RECOVERY_RAMP_END[1],
            group_key: "main") ].freeze
        end
      elsif @variation_key == "a"
        [ steady(@duration, rules::ENDURANCE_STEADY_TARGET) ].freeze
      else
        count = [ @duration / (2 * rules::ENDURANCE_BLOCK_SECONDS), 1 ].max * 2
        units, remainder = (@duration / rules::MINIMUM_STEP_SECONDS).divmod(count)
        Array.new(count) do |index|
          seconds = (units + (index < remainder ? 1 : 0)) * rules::MINIMUM_STEP_SECONDS
          low = rules::ENDURANCE_LOW_TARGET
          high = rules::ENDURANCE_HIGH_TARGET
          start_target, end_target = index.even? ? [ low, high ] : [ high, low ]
          if @variation_key == "b"
            steady(seconds, start_target).with(label: index.even? ? "Low endurance" : "High endurance")
          else
            steady(seconds, start_target).with(
              kind: "ramp",
              label: index.even? ? "Rising endurance" : "Falling endurance",
              end_target_low_pct_ftp: end_target[0],
              end_target_high_pct_ftp: end_target[1])
          end
        end.freeze
      end
    end

    private

    def steady(seconds, target, group = "main")
      StepDefinition.new(
        kind: "steady",
        label: group == "main" ? Training::V1::Rules::SUBTYPE_NAMES.fetch(@subtype) : "Easy between blocks",
        duration_seconds: seconds,
        target_low_pct_ftp: target[0],
        target_high_pct_ftp: target[1],
        group_key: group)
    end
  end
end
