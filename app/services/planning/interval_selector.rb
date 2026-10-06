require_relative "rules"

module Planning
  # Selects interval workout subtype based on goal, discipline, phase and ordinal.
  class IntervalSelector
    def initialize(goal:, discipline:, phase:, ordinal:)
      @goal = goal.to_sym
      @discipline = discipline.to_sym
      @phase = phase.to_sym
      @ordinal = ordinal
    end

    def call
      cycle = if @goal == :event && Rules::EVENT_DISCIPLINE_CYCLES.dig(@phase, @discipline)
        Rules::EVENT_DISCIPLINE_CYCLES.dig(@phase, @discipline)
      else
        Rules::INTERVAL_CYCLES.fetch(@phase).fetch(@goal)
      end
      cycle.fetch(@ordinal % cycle.length)
    end
  end
end
