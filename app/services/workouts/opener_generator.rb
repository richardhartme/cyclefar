require_relative "step_definition"
require_relative "step_sequence"
require_relative "workout_definition"
require_relative "../training/v1/rules"

module Workouts
  class OpenerGenerator
    def initialize(duration_minutes:, phase: :taper, goal: :event, discipline: :road)
      raise ArgumentError, "opener duration must be 30 to 45 minutes" unless duration_minutes.is_a?(Integer) && duration_minutes.between?(30, 45)

      @duration_minutes = duration_minutes
      @phase = phase.to_s
      @goal = goal.to_s
      @discipline = discipline.to_s
    end

    def call
      steps = [
        ramp("Warm up", 600, [ 45, 55 ], [ 70, 70 ], "warm_up"),
        *repetitions("Threshold activation", 60, [ 100, 108 ], "activation", 3, 120, [ 50, 60 ]),
        *repetitions("VO2 activation", 30, [ 108, 118 ], "activation", 3, 90, [ 50, 60 ])
      ]
      remaining = @duration_minutes * 60 - steps.sum(&:duration_seconds) - 300
      steps << steady("Easy riding", remaining, [ 50, 65 ], "filler") if remaining.positive?
      steps << ramp("Cool down", 300, [ 55, 60 ], [ 40, 50 ], "cool_down")
      WorkoutDefinition.new(engine_version: Training::V1::Rules::ENGINE_VERSION, subtype: "endurance",
        duration_minutes: @duration_minutes, requested_progression_level: nil, progression_level: nil, variation_key: "a",
        phase: @phase, goal: @goal, discipline: @discipline, name: "Event Opener", purpose: "Taper activation before your event.",
        main_set_summary: "Brief activation efforts with ample recovery", steps: position(steps), reason_codes: [ "event_opener" ])
    end

    private

    def repetitions(label, work_seconds, work_target, group_key, count, recovery_seconds, recovery_target)
      count.times.flat_map do |index|
        work = steady(label, work_seconds, work_target, group_key, index + 1)
        recovery = steady("Easy recovery", recovery_seconds, recovery_target, "recovery", index + 1)
        [ work, recovery ]
      end
    end

    def steady(label, seconds, target, group_key, iteration = nil)
      StepDefinition.new(kind: "steady", label: label, duration_seconds: seconds, target_low_pct_ftp: target[0],
        target_high_pct_ftp: target[1], group_key: group_key, group_iteration: iteration)
    end

    def ramp(label, seconds, start_target, end_target, group_key)
      StepDefinition.new(kind: "ramp", label: label, duration_seconds: seconds, target_low_pct_ftp: start_target[0],
        target_high_pct_ftp: start_target[1], end_target_low_pct_ftp: end_target[0], end_target_high_pct_ftp: end_target[1], group_key: group_key)
    end

    def position(steps)
      steps.each_with_index.map { |step, index| step.with(position: index + 1) }.freeze
    end
  end
end
