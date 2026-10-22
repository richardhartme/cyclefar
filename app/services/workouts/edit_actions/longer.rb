module Workouts
  module EditActions
    class Longer < Base
      def duration = @workout.duration_minutes + Training::Rules::SHORTER_LONGER_STEP_MINUTES
    end
  end
end
