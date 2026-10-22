module Workouts
  # Creates new planned workouts (openers and regular) on a training plan.
  class Creator
    DEFAULT_PROGRESSION_LEVEL = 1

    def initialize(plan)
      @plan = plan
    end

    def create!(scheduled_on:, subtype:, duration_minutes:)
      @plan.with_lock { create_under_lock!(scheduled_on: scheduled_on, subtype: subtype, duration_minutes: duration_minutes) }
    end

    def create_under_lock!(scheduled_on:, subtype:, duration_minutes:)
      validate_destination!(scheduled_on)
      kind, definition = definition_for(scheduled_on, subtype, duration_minutes)
      metrics = Metrics::WorkoutCalculator.new(
        steps: definition.steps,
        ftp_watts: @plan.ftp_watts_for_planning).call

      PlannedWorkout.transaction do
        workout = @plan.planned_workouts.build(
          plan_phase: phase_for(scheduled_on),
          scheduled_on: scheduled_on,
          kind: kind,
          intent: intent_for(kind, definition.subtype))
        workout.apply_definition(definition, metrics)
        workout.save!
        workout
      end
    end
    private :create_under_lock!

    def validate_destination!(scheduled_on)
      DestinationValidator.new(@plan).validate!(scheduled_on)
    end

    private

    def definition_for(scheduled_on, subtype, duration_minutes)
      subtype = subtype.to_sym
      kind = subtype == :opener ? :opener : :workout
      definition = DefinitionFactory.for(@plan).build(
        kind: kind,
        subtype: subtype,
        duration_minutes: Integer(duration_minutes),
        phase: phase_for(scheduled_on).kind,
        progression_level: DEFAULT_PROGRESSION_LEVEL,
        variation_key: (Variations.for_generation(subtype) unless kind == :opener))
      [ kind, definition ]
    end

    def intent_for(kind, subtype)
      return :intervals if kind == :opener || subtype.to_sym == :over_under

      subtype
    end

    def phase_for(date)
      @plan.plan_phases.find { |phase| date.between?(phase.starts_on, phase.ends_on) } ||
        raise(ArgumentError, "Choose a date covered by a plan phase")
    end
  end
end
