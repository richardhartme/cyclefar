module IntervalsIcu
  class EligibleWorkouts
    def initialize(plan)
      @plan = plan
    end

    def call
      candidates = @plan.planned_workouts.planned.structured.where(kind: %w[workout opener])
        .where("scheduled_on >= ?", Date.current).includes(:workout_steps, :intervals_icu_sync).order(:scheduled_on)
      candidates = candidates.where.not(scheduled_on: @plan.target_event.event_on) if @plan.target_event
      time_off_periods = @plan.time_off_periods.to_a
      candidates.reject { |workout| time_off_periods.any? { |time_off| workout.scheduled_on.between?(time_off.starts_on, time_off.ends_on) } }
    end
  end
end
