module Workouts
  module EditActions
    class Base
      def initialize(workout, subtype: nil, duration_minutes: nil, progression_level: nil)
        @workout = workout
        @subtype = subtype
        @duration_minutes = duration_minutes
        @progression_level = progression_level
      end

      def level = @workout.progression_level || 1
      def variation_key = @workout.variation_key
      def duration = @workout.duration_minutes
      def subtype = @workout.subtype
      def load_adjustments = {}
    end
  end
end
