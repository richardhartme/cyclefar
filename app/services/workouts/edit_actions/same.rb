module Workouts
  module EditActions
    class Same < Base
      def variation_key
        Variations.next_key(@workout.variation_key || Variations.default_key(@workout.subtype), subtype: @workout.subtype)
      end
    end
  end
end
