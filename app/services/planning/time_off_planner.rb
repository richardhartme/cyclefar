module Planning
  class TimeOffPlanner
    def initialize(plan:)
      @plan = plan
    end

    def add!(attributes)
      TrainingPlan.transaction do
        period = @plan.time_off_periods.create!(attributes)
        FuturePrescriber.new(plan: @plan, slots: active_slots).replace!(period.starts_on..@plan.ends_on)
        period
      end
    end

    def remove!(period)
      raise ArgumentError, "Time off belongs to a different plan" unless period.training_plan == @plan

      TrainingPlan.transaction do
        starts_on = period.starts_on
        period.destroy!
        FuturePrescriber.new(plan: @plan, slots: active_slots).replace!(starts_on..@plan.ends_on)
      end
    end

    private

    def active_slots
      template = @plan.availability_templates.includes(:availability_slots).select do |candidate|
        candidate.effective_from <= Date.current && (candidate.effective_until.nil? || candidate.effective_until >= Date.current)
      end.max_by { |candidate| [ candidate.one_week_override? ? 1 : 0, candidate.effective_from ] }
      raise ArgumentError, "No availability template applies today" unless template

      template.availability_slots
    end
  end
end
