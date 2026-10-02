require_relative "rules"

module Training
  module V1
    # Calculates progression levels with bias and maximum bounds.
    module Progression
      def self.level(baseline:, bias: 0, maximum: nil)
        levels = Rules::PROGRESSION_LEVELS
        result = (Integer(baseline) + Integer(bias).clamp(*Rules::PROGRESSION_BIAS_BOUNDS)).clamp(levels.begin, levels.end)
        maximum ? [ result, Integer(maximum) ].min.clamp(levels.begin, levels.end) : result
      end
    end
  end
end
