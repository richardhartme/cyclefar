require_relative "rules"

module Planning
  # One calendar schedule shared by previews, presentation and load checks.
  class RecoverySchedule
    def initialize(starts_on:, ends_on:, phases:, hard_weeks: nil)
      @starts_on, @ends_on, @phases, @hard_weeks = starts_on, ends_on, phases, hard_weeks
    end

    def flags
      starts = (@starts_on.beginning_of_week..@ends_on.beginning_of_week).step(7).to_a
      result = starts.to_h { |date| [ date, false ] }
      return result unless @hard_weeks

      transitions = @phases.drop(1).select { |phase| %w[build speciality].include?(phase.kind) }
      previous = @starts_on.beginning_of_week - 7
      nominal = @starts_on.beginning_of_week + @hard_weeks * 7
      while nominal <= @ends_on
        # For a midweek boundary, use the last full calendar week before it.
        # Resume N hard weeks after an alignment; never create adjacent recoveries.
        aligned = transitions.map { |phase| phase.starts_on.beginning_of_week - 7 }.select do |date|
          (date - nominal).abs <= 7 && date >= @starts_on && date > previous + 7 && eligible?(date)
        end.min_by { |date| [ (date - nominal).abs, date ] }
        selected = aligned || nominal
        result[selected] = true if result.key?(selected) && eligible?(selected)
        previous = selected
        nominal = selected + (@hard_weeks + 1) * 7
      end
      result
    end

    private

    def eligible?(date)
      @phases.none? { |phase| phase.kind == "taper" && phase.starts_on <= date + 6 && phase.ends_on >= date }
    end
  end
end
