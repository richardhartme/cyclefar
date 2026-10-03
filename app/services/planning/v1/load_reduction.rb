module Planning
  module V1
    # Pure generation alternatives for §27. Endurance keeps its saved profile;
    # specific interval intents keep their subtype. No target leaves its band.
    class LoadReduction
      def self.options(definition, stage:, intent:)
        new(definition, intent: intent).options(stage)
      end

      def initialize(definition, intent:)
        @definition = definition
        @intent = intent.to_s
      end

      def options(stage)
        case stage
        when :level
          return [] unless @definition.progression_level

          (@definition.progression_level - 1).downto(1).map { |level| generate(progression_level: level) }
        when :variation
          return [] if @definition.subtype == "endurance"

          Workouts::Variations.keys_for(@definition.subtype).reject { |key| key == @definition.variation_key }
            .map { |key| generate(variation_key: key) }
        when :target
          return [] if @definition.load_adjustments["lower_targets"]

          [ generate(load_adjustments: @definition.load_adjustments.merge("lower_targets" => true)) ]
        when :subtype
          return [] unless @intent == "intervals" && @definition.progression_level

          compatible_lower_subtypes.map do |subtype|
            generate(subtype: subtype, progression_level: 1, variation_key: Workouts::Variations.default_key(subtype))
          end
        when :filler
          return [] unless @definition.progression_level && !@definition.load_adjustments["easy_filler"]

          # Reuse V1's valid short main sets and fill the remaining scheduled
          # time with easy riding; never shorten normal availability.
          [ generate(progression_level: 1, load_adjustments: @definition.load_adjustments.merge("easy_filler" => true)) ]
        else
          raise ArgumentError, "Unsupported load reduction stage"
        end
      end

      private

      def generate(**changes)
        Workouts::Generator.new(
          subtype: @definition.subtype,
          duration_minutes: @definition.duration_minutes,
          progression_level: @definition.progression_level || 1,
          variation_key: @definition.variation_key,
          phase: @definition.phase,
          goal: @definition.goal,
          discipline: @definition.discipline,
          load_adjustments: @definition.load_adjustments,
          **changes).call
      end

      def compatible_lower_subtypes
        # Follow the documented aerobic step-down direction, restricted to
        # subtypes already valid in this goal/phase's selection cycle.
        lower = case @definition.subtype
        when "vo2_max", "over_under" then %i[threshold sweet_spot tempo]
        when "threshold" then %i[sweet_spot tempo]
        when "sweet_spot" then %i[tempo]
        else []
        end
        phase = @definition.phase.to_sym
        goal = @definition.goal.to_sym
        cycles = if goal == :event && phase != :base
          Rules::EVENT_DISCIPLINE_CYCLES.fetch(phase, {}).fetch(@definition.discipline.to_sym, [])
        else
          Rules::INTERVAL_CYCLES.fetch(phase, {}).fetch(goal, [])
        end
        lower & cycles
      end
    end
  end
end
