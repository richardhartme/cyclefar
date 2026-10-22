module Workouts
  module EditActions
    class Adapt < Base
      def level = Integer(@progression_level).clamp(1, 7)
      def load_adjustments = @workout.generation_context.fetch("load_adjustments", {})
    end
  end
end
