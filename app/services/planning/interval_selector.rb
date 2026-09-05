require_relative "v1/rules"

module Planning
  class IntervalSelector
    def initialize(goal:, discipline:, phase:, ordinal:)
      @goal = goal.to_sym
      @discipline = discipline.to_sym
      @phase = phase.to_sym
      @ordinal = ordinal
    end

    def call
      cycle = if @goal == :event && V1::Rules::EVENT_DISCIPLINE_CYCLES.dig(@phase, @discipline)
        V1::Rules::EVENT_DISCIPLINE_CYCLES.dig(@phase, @discipline)
      else
        V1::Rules::INTERVAL_CYCLES.fetch(@phase).fetch(@goal)
      end
      cycle.fetch(@ordinal % cycle.length)
    end
  end
end
