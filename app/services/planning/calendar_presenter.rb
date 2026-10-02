module Planning
  # Formats plan into weekly calendar view with load metrics and phase labels.
  class CalendarPresenter
    Week = Data.define(:starts_on, :ends_on, :days, :phase_label, :recovery_week, :duration_minutes, :estimated_tss, :estimated_work_kj)

    def initialize(plan = nil, starts_on: Date.current.beginning_of_week - 7, ends_on: starts_on.beginning_of_week + 27)
      @plan = plan
      @starts_on = plan&.starts_on || starts_on
      @ends_on = plan&.ends_on || ends_on
      @workouts_by_date = plan ? plan.planned_workouts.includes(:workout_steps, :plan_phase).order(:scheduled_on).group_by(&:scheduled_on) : {}
      @time_off_by_date = plan ? plan.time_off_periods.flat_map { |period| (period.starts_on..period.ends_on).map { |date| [ date, period ] } }.to_h : {}
    end

    def weeks
      (@starts_on.beginning_of_week..@ends_on.beginning_of_week).step(7).map do |starts_on|
        workouts = days_for(starts_on).flat_map { |date| @workouts_by_date.fetch(date, []) }
        Week.new(
          starts_on: starts_on,
          ends_on: starts_on + 6,
          days: days_for(starts_on),
          phase_label: phase_label(starts_on),
          recovery_week: recovery_week?(starts_on),
          duration_minutes: workouts.sum { |workout| workout.duration_minutes.to_i },
          estimated_tss: workouts.sum { |workout| workout.estimated_tss.to_f },
          estimated_work_kj: workouts.sum { |workout| workout.estimated_work_kj.to_f })
      end
    end

    def workouts_on(date)
      @workouts_by_date.fetch(date, [])
    end

    def event_on(date)
      @plan&.target_event if @plan&.target_event&.event_on == date
    end

    def time_off_on(date)
      @time_off_by_date[date]
    end

    private

    def days_for(starts_on)
      (starts_on..starts_on + 6).to_a
    end

    def phase_label(starts_on)
      return "No plan" unless @plan

      phase = @plan.plan_phases.find { |candidate| candidate.ends_on >= starts_on && candidate.starts_on <= starts_on + 6 }
      phase&.kind&.humanize || "Training"
    end

    def recovery_week?(starts_on)
      return false unless @plan
      return false unless @plan.hard_recovery_cycle?
      return false if @plan.plan_phases.any? { |phase| phase.kind_taper? && phase.starts_on <= starts_on + 6 && phase.ends_on >= starts_on }

      index = ((starts_on - @plan.starts_on.beginning_of_week) / 7).to_i
      index % (@plan.hard_weeks_before_recovery + 1) == @plan.hard_weeks_before_recovery
    end
  end
end
