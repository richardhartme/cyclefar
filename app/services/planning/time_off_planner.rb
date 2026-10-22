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
      templates = @plan.availability_templates.includes(:availability_slots).to_a
      dates = ([ starts_on, @plan.starts_on, Date.current ].max..@plan.ends_on).to_a
      dates_by_template = dates.group_by do |date|
        template = AvailabilityTemplate.for_date(templates, date)
        raise ArgumentError, "No availability template applies on #{date.to_fs(:long)}" unless template

        template
      end

      dates_by_template.each do |template, scheduled_dates|
        FuturePrescriber.new(plan: @plan, slots: template.availability_slots).replace!(scheduled_dates)
      end
    end
  end
end
