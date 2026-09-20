module Planning
  class TimeOffPlanner
    def initialize(plan:)
      @plan = plan
    end

    def add!(attributes)
      TrainingPlan.transaction do
        period = @plan.time_off_periods.create!(attributes)
        re_prescribe!(period.starts_on)
        period
      end
    end

    def remove!(period)
      raise ArgumentError, "Time off belongs to a different plan" unless period.training_plan == @plan

      TrainingPlan.transaction do
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
        template = templates.select do |candidate|
          candidate.effective_from <= date && (candidate.effective_until.nil? || candidate.effective_until >= date)
        end.max_by { |candidate| [ candidate.one_week_override? ? 1 : 0, candidate.effective_from ] }
        raise ArgumentError, "No availability template applies on #{date.to_fs(:long)}" unless template

        template
      end

      dates_by_template.each do |template, scheduled_dates|
        FuturePrescriber.new(plan: @plan, slots: template.availability_slots).replace!(scheduled_dates)
      end
    end
  end
end
