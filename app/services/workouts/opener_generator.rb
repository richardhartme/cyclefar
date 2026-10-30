module Workouts
  # Generates pre-event opener workouts with threshold and VO2 activation efforts.
  class OpenerGenerator
    def initialize(duration_minutes:, phase: :taper, goal: :event, discipline: :road)
      range = Training::Rules::OPENER_DURATION_MINUTES
      raise ArgumentError, "opener duration must be #{range.min} to #{range.max} minutes" unless duration_minutes.is_a?(Integer) && range.cover?(duration_minutes)

      @duration_minutes = duration_minutes
      @phase = phase.to_s
      @goal = goal.to_s
      @discipline = discipline.to_s
    end

    def call
      warm_up = Training::Rules::OPENER_WARM_UP
      steps = [
        ramp("Warm up", warm_up[:seconds], warm_up[:start], warm_up[:finish], "warm_up"),
        *Training::Rules::OPENER_ACTIVATIONS.flat_map { |activation| repetitions(activation) }
      ]
      remaining = @duration_minutes * 60 - steps.sum(&:duration_seconds) - Training::Rules::COOL_DOWN_SECONDS
      steps << steady("Easy riding", remaining, Training::Rules::OPENER_FILLER_TARGET, "filler") if remaining.positive?
      steps << ramp("Cool down", Training::Rules::COOL_DOWN_SECONDS, Training::Rules::COOL_DOWN_START, Training::Rules::COOL_DOWN_END, "cool_down")
      WorkoutDefinition.new(
        engine_version: Training::Rules::ENGINE_VERSION,
        subtype: "endurance",
        duration_minutes: @duration_minutes,
        requested_progression_level: nil,
        progression_level: nil,
        variation_key: "activation",
        phase: @phase,
        goal: @goal,
        discipline: @discipline,
        name: "Event Opener",
        purpose: "Taper activation before your event.",
        main_set_summary: "Brief activation efforts with ample recovery",
        steps: position(steps),
        reason_codes: [ "event_opener" ])
    end

    private

    def repetitions(activation)
      activation[:repetitions].times.flat_map do |index|
        work = steady(activation[:label], activation[:work_seconds], activation[:target], "activation", index + 1)
        recovery = steady("Easy recovery", activation[:recovery_seconds], Training::Rules::TARGETS[:easy], "recovery", index + 1)
        [ work, recovery ]
      end
    end

    def steady(label, seconds, target, group_key, iteration = nil)
      StepDefinition.new(
        kind: "steady",
        label: label,
        duration_seconds: seconds,
        target_low_pct_ftp: target[0],
        target_high_pct_ftp: target[1],
        group_key: group_key,
        group_iteration: iteration)
    end

    def ramp(label, seconds, start_target, end_target, group_key)
      StepDefinition.new(
        kind: "ramp",
        label: label,
        duration_seconds: seconds,
        target_low_pct_ftp: start_target[0],
        target_high_pct_ftp: start_target[1],
        end_target_low_pct_ftp: end_target[0],
        end_target_high_pct_ftp: end_target[1],
        group_key: group_key)
    end

    def position(steps)
      steps.each_with_index.map { |step, index| step.with(position: index + 1) }.freeze
    end
  end
end
