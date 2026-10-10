module Workouts
  class Remover
    def initialize(workout)
      @workout = workout
    end

    def call
      @workout.training_plan.with_lock do
        @workout.reload
        raise ArgumentError, "Completed workouts cannot be removed" if @workout.completed?
        raise ArgumentError, "Only workouts in an active plan can be removed" unless @workout.training_plan.active?

        # Nullify the sync association so the next manual sync can remove its
        # owned remote event, including after an uncertain earlier upload.
        @workout.destroy!
      end
    end
  end
end
