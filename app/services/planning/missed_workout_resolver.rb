module Planning
  # Handles missed workouts: mark, move to another date, or replan forward.
  class MissedWorkoutResolver
    def initialize(workout)
      @workout = workout
      raise ArgumentError, "Only planned workouts can be resolved as missed" unless workout.planned?
    end

    def resolve!(mode:, destination: nil)
      @workout.training_plan.with_lock do
        @workout.reload
        raise ArgumentError, "Only planned workouts can be resolved as missed" unless @workout.planned?

        resolve_under_lock!(mode: mode, destination: destination)
      end
    end

    private

    def resolve_under_lock!(mode:, destination:)
      case mode.to_s
      when "leave_unchanged"
        mark_missed!
      when "replan"
        @workout.training_plan.with_lock do
          mark_missed!
          replan_upcoming_workouts!
        end
      when "move"
        Workouts::Mover.new(@workout).move_to!(destination: Date.iso8601(destination.to_s))
      else
        raise ArgumentError, "Choose a missed-workout resolution"
      end
    end

    def mark_missed!
      @workout.update!(status: :missed)
    end

    def replan_upcoming_workouts!
      plan = @workout.training_plan
      template = active_template_for(plan, Date.current)
      raise ArgumentError, "No availability template applies today" unless template

      FuturePrescriber.new(plan: plan, slots: template.availability_slots).replace!(Date.current..[ Date.current + 13, plan.ends_on ].min)
    end

    def active_template_for(plan, date)
      AvailabilityTemplate.for_date(plan.availability_templates.includes(:availability_slots).to_a, date)
    end
  end
end
