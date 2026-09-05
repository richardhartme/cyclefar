require_relative "step_definition"

module Workouts
  module StepSequence
    def self.normalize(steps)
      sequence = steps.to_a.map { |step| StepDefinition.from(step) }.sort_by(&:position)
      if sequence.empty? || sequence.map(&:position) != (1..sequence.length).to_a
        raise ArgumentError, "steps must have consecutive unique positions starting at 1"
      end
      sequence.freeze
    end
  end
end
