require_relative "rules"

module Planning
  # Planned sessions support future breaks; missed/special records cannot
  # establish a reached or projected level. Selection is by recent family.
  class PreBreakProgression
    def self.levels(workouts, before:)
      recent = workouts.select do |workout|
        workout.scheduled_on < before && workout.kind == "workout" && workout.status != "missed" && workout.progression_level
      end.sort_by(&:scheduled_on).reverse
      Training::Rules::LADDERS.keys.to_h do |subtype|
        family = Training::Rules::COMPARABLE_FAMILIES.find { |members| members.include?(subtype.to_s) } || [ subtype.to_s ]
        latest = recent.find { |workout| family.include?(workout.subtype) }
        [ subtype.to_s, latest&.progression_level || 1 ]
      end
    end
  end
end
