module Planning
  # Manages time-off periods and re-prescribes workouts in affected date ranges.
  class TimeOffPlanner
    def initialize(plan:)
      @plan = plan
    end

    def add!(attributes)
      @plan.with_lock do
        period = @plan.time_off_periods.create!(attributes)
        re_prescribe!(period.starts_on)
        period
      end
    end

    def remove!(period)
      raise ArgumentError, "Time off belongs to a different plan" unless period.training_plan == @plan

      @plan.with_lock do
        starts_on = period.starts_on
        period.destroy!
        re_prescribe!(starts_on)
      end
    end

    private

    def re_prescribe!(starts_on)
      FuturePrescriber.replace_with_templates!(plan: @plan, dates: [ starts_on, @plan.starts_on, Date.current ].max..@plan.ends_on)
    end
  end
end
