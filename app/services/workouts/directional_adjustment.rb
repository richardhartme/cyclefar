module Workouts
  # Selects a valid replacement whose canonical load moves in the requested direction.
  class DirectionalAdjustment
    Result = Data.define(:definition, :metrics, :current_metrics)
    class LimitReached < ArgumentError; end

    def initialize(action:, steps:, ftp_watts:, progression_level:, maximum_level: nil, tss_scale: nil, **generator_attributes)
      @action = action.to_s
      raise ArgumentError, "Unsupported directional adjustment" unless %w[easier harder].include?(@action)

      @steps, @ftp_watts = steps, ftp_watts
      @level, @maximum_level = progression_level, maximum_level
      @tss_scale = tss_scale
      @attributes = generator_attributes
    end

    def call
      current_metrics = metrics_for(@steps)
      candidate_levels.each do |level|
        variation_keys.each do |variation|
          definition = Generator.new(**@attributes, progression_level: level, variation_key: variation).call
          # A higher requested level may fit back down to a lower ladder entry.
          next if @action == "harder" && definition.progression_level && definition.progression_level < (@level || 1)

          metrics = metrics_for(definition.steps)
          if moves_load?(metrics.estimated_tss, current_metrics.estimated_tss)
            return Result.new(definition: definition, metrics: metrics, current_metrics: current_metrics)
          end
        end
      end
      direction, suggestion = @action == "easier" ? [ "lower", "Shorter" ] : [ "higher", "Longer" ]
      raise LimitReached, "No #{direction}-load option is available at this duration. Try #{suggestion} or Change workout."
    end

    private

    def candidate_levels
      bounds = Training::Rules::PROGRESSION_LEVELS
      return [ bounds.begin ] unless Training::Rules::LADDERS.key?(@attributes.fetch(:subtype).to_sym)

      current = @level || bounds.begin
      maximum = (@maximum_level || bounds.end).clamp(bounds.begin, bounds.end)
      directional = @action == "easier" ? (bounds.begin...current).to_a.reverse : ((current + 1)..maximum).to_a
      (directional + [ current ]).select { |level| level <= maximum }
    end

    def variation_keys
      keys = Variations.keys_for(@attributes.fetch(:subtype))
      current = @attributes[:variation_key] || keys.first
      # Prefer the saved profile; ties use the declared rule order, never sampling.
      [ current ] + (keys - [ current ])
    end

    def moves_load?(proposed, current)
      if @action == "easier"
        proposed < current && displayed_tss(proposed) < displayed_tss(current)
      else
        proposed > current && displayed_tss(proposed) > displayed_tss(current)
      end
    end

    def displayed_tss(tss)
      # Match the persisted decimal precision before the UI's whole-number rounding.
      (@tss_scale ? tss.round(@tss_scale) : tss).round
    end

    def metrics_for(steps)
      Metrics::WorkoutCalculator.new(steps: steps, ftp_watts: @ftp_watts).call
    end
  end
end
