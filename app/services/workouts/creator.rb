module Workouts
  class Creator
    DEFAULT_PROGRESSION_LEVEL = 1

    def initialize(plan)
      @plan = plan
    end

    def create!(scheduled_on:, subtype:, duration_minutes:)
      validate_destination!(scheduled_on)
      kind, definition = definition_for(scheduled_on, subtype, duration_minutes)
      metrics = Metrics::WorkoutCalculator.new(
        steps: definition.steps,
        ftp_watts: current_ftp_watts).call

      PlannedWorkout.transaction do
        workout = @plan.planned_workouts.build(
          plan_phase: phase_for(scheduled_on),
          scheduled_on: scheduled_on,
          kind: kind,
          intent: intent_for(kind, definition.subtype),
          subtype: definition.subtype,
          duration_minutes: definition.duration_minutes,
          progression_level: definition.progression_level,
          variation_key: definition.variation_key,
          name: definition.name,
          purpose: definition.purpose,
          detail_status: :structured,
          estimated_np_watts: metrics.estimated_np_watts,
          estimated_if: metrics.estimated_if,
          estimated_tss: metrics.estimated_tss,
          estimated_work_kj: metrics.estimated_work_kj)
        definition.steps.each { |step| workout.workout_steps.build(step.to_h) }
        workout.save!
        workout
      end
    end

    def validate_destination!(scheduled_on)
      raise ArgumentError, "Choose a date inside this plan" unless scheduled_on.between?(@plan.starts_on, @plan.ends_on)
      raise ArgumentError, "That date already has a workout" if @plan.planned_workouts.exists?(scheduled_on: scheduled_on)
      raise ArgumentError, "Workouts cannot be added during time off" if @plan.time_off_periods.where("starts_on <= ? AND ends_on >= ?", scheduled_on, scheduled_on).exists?
      raise ArgumentError, "Workouts cannot be added on the target event date" if @plan.target_event&.event_on == scheduled_on

      phase_for(scheduled_on)
    end

    private

    def definition_for(scheduled_on, subtype, duration_minutes)
      phase = phase_for(scheduled_on)
      if subtype.to_s == "opener"
        return [ :opener, OpenerGenerator.new(
          duration_minutes: Integer(duration_minutes),
          phase: phase.kind,
          goal: @plan.goal,
          discipline: @plan.discipline).call ]
      end

      [ :workout, Generator.new(
        subtype: subtype,
        duration_minutes: Integer(duration_minutes),
        progression_level: DEFAULT_PROGRESSION_LEVEL,
        phase: phase.kind,
        goal: @plan.goal,
        discipline: @plan.discipline).call ]
    end

    def intent_for(kind, subtype)
      return :intervals if kind == :opener || subtype == "over_under"

      subtype
    end

    def phase_for(date)
      @plan.plan_phases.find { |phase| date.between?(phase.starts_on, phase.ends_on) } ||
        raise(ArgumentError, "Choose a date covered by a plan phase")
    end

    def current_ftp_watts
      RiderProfile.current.ftp_watts || @plan.initial_ftp_watts
    end
  end
end
