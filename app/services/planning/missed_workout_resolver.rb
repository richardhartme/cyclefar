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
        raise ArgumentError, "Only past or current workouts can be marked missed" if @workout.scheduled_on > Date.current

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
      FuturePrescriber.replace_with_templates!(plan: plan, dates: Date.current..[ Rules.horizon_end(Date.current), plan.ends_on ].min)
    end
  end
end
