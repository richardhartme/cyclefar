module Workouts
  class DestinationValidator
    def initialize(plan)
      @plan = plan
    end

    # Call under the plan lock for mutations. Only Move excludes its source,
    # allowing a same-date move; Add and Copy require a genuinely empty date.
    def validate!(date, excluding_workout: nil)
      raise ArgumentError, "Choose an empty date inside this plan" unless date.between?(@plan.starts_on, @plan.ends_on)

      occupied = @plan.planned_workouts.where(scheduled_on: date)
      occupied = occupied.where.not(id: excluding_workout.id) if excluding_workout
      raise ArgumentError, "That date already has a workout" if occupied.exists?
      raise ArgumentError, "Workouts cannot be scheduled during time off" if @plan.time_off_periods.where("starts_on <= ? AND ends_on >= ?", date, date).exists?
      raise ArgumentError, "Workouts cannot be scheduled on the target event date" if @plan.target_event&.event_on == date

      @plan.plan_phases.find_by("starts_on <= ? AND ends_on >= ?", date, date) ||
        raise(ArgumentError, "Choose a date covered by a plan phase")
    end
  end
end
