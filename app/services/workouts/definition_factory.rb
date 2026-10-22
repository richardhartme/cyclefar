module Workouts
  # Single place that chooses between Generator and OpenerGenerator.
  class DefinitionFactory
    def self.for(plan) = new(goal: plan.goal, discipline: plan.discipline)

    def initialize(goal:, discipline:)
      @goal = goal
      @discipline = discipline
    end

    def build(kind:, duration_minutes:, phase:, subtype: nil, progression_level: 1, variation_key: nil, load_adjustments: {})
      if kind.to_s == "opener"
        OpenerGenerator.new(duration_minutes: duration_minutes, phase: phase, goal: @goal, discipline: @discipline).call
      else
        Generator.new(
          subtype: subtype,
          duration_minutes: duration_minutes,
          progression_level: progression_level,
          variation_key: variation_key,
          phase: phase,
          goal: @goal,
          discipline: @discipline,
          load_adjustments: load_adjustments).call
      end
    end

    # Rebuilds a stored workout's definition. Pass overrides, or a block
    # returning them that only runs for regular workouts (openers have no level).
    def for_workout(workout, **overrides)
      overrides = yield if block_given? && !workout.opener?
      build(
        kind: workout.kind,
        duration_minutes: workout.duration_minutes,
        phase: workout.plan_phase&.kind || "base",
        subtype: workout.subtype,
        progression_level: workout.progression_level || 1,
        variation_key: workout.variation_key,
        load_adjustments: workout.generation_context.fetch("load_adjustments", {}),
        **overrides)
    end
  end
end
