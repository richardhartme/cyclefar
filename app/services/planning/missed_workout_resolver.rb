module Planning
  class MissedWorkoutResolver
    def initialize(workout)
      @workout = workout
      raise ArgumentError, "Only planned workouts can be resolved as missed" unless workout.planned?
    end

    def resolve!(mode:, destination: nil)
      case mode.to_s
      when "leave_unchanged"
        @workout.destroy!
      when "replan"
        TrainingPlan.transaction do
          @workout.destroy!
          replan_upcoming_workouts!
        end
      when "move"
        move!(Date.iso8601(destination.to_s))
      else
        raise ArgumentError, "Choose a missed-workout resolution"
      end
    end

    private

    def move!(date)
      plan = @workout.training_plan
      raise ArgumentError, "Choose an empty date inside this plan" unless date.between?(plan.starts_on, plan.ends_on)
      raise ArgumentError, "That date already has a workout" if plan.planned_workouts.where(scheduled_on: date).where.not(id: @workout.id).exists?

      phase = plan.plan_phases.find { |item| date.between?(item.starts_on, item.ends_on) }
      @workout.update!(scheduled_on: date, plan_phase: phase)
    end

    def replan_upcoming_workouts!
      plan = @workout.training_plan
      template = active_template_for(plan, Date.current)
      raise ArgumentError, "No availability template applies today" unless template

      FuturePrescriber.new(plan: plan, slots: template.availability_slots).replace!(Date.current..[ Date.current + 13, plan.ends_on ].min)
    end

    def active_template_for(plan, date)
      plan.availability_templates.includes(:availability_slots).select do |template|
        template.effective_from <= date && (template.effective_until.nil? || template.effective_until >= date)
      end.max_by { |template| [ template.one_week_override? ? 1 : 0, template.effective_from ] }
    end
  end
end
