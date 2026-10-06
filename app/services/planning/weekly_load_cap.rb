require_relative "rules"

module Planning
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
      %i[level variation target subtype filler].each do |stage|
        loop do
          return adjusted if adjusted.sum(&:estimated_tss) <= limit

          replacement = nil
          adjusted.select(&:adjustable?).sort_by { |item| [ -item.estimated_tss, item.scheduled_on ] }.each do |candidate|
            # A ladder's TSS is not monotonic. Accept only a real reduction;
            # the caller can search past an intermediate higher-load level.
            option = yield(candidate, stage).find { |item| item.estimated_tss < candidate.estimated_tss - 0.000001 }
            next unless option

            replacement = [ adjusted.index(candidate), option ]
            break
          end
          break unless replacement

          adjusted[replacement.first] = replacement.last
        end
      end
      adjusted
    end
  end
end
