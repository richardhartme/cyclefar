module Workouts
  module EditActions
    class Change < Base
      def variation_key = Variations.for_generation(@subtype)
      def duration = Integer(@duration_minutes)
      def subtype = @subtype.to_s
    end
  end
end
