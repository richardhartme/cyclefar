require_relative "rules"

module Planning
  module V1
    class WeeklyLoadCap
      def self.limit(reference_tss)
        reference_tss * (1 + Rules::HARD_WEEK_GROWTH_CAP)
      end

      def self.warning(week_start)
        "Week of #{week_start}: your schedule keeps projected load above the 8% growth target."
      end

      # Callers define which prescriptions can change. Structured history and
      # explicit rider edits are fixed when the horizon materialises.
      def self.reduce(items, limit:)
        adjusted = items.dup
        while adjusted.sum(&:estimated_tss) > limit
          candidate = adjusted.select { |item| item.adjustable? && item.progression_level.to_i > 1 }
            .max_by { |item| [ item.estimated_tss, -item.scheduled_on.jd ] }
          break unless candidate

          adjusted[adjusted.index(candidate)] = yield(candidate)
        end
        adjusted
      end
    end
  end
end
