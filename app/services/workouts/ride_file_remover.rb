module Workouts
  # Removes a completed workout's ride file and its ridden metrics. The
  # workout's completion snapshot and feedback are untouched.
  class RideFileRemover
    def initialize(workout)
      @workout = workout
    end

    def call
      @workout.training_plan.with_lock do
        @workout.reload.workout_activity&.destroy!
      end
    end
  end
end
