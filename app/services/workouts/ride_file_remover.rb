module Workouts
  # Removes a completed workout's ride. An uploaded activity is deleted with
  # its file; a Garmin ride is unlinked and kept (GAR-008). The workout's
  # completion snapshot and feedback are untouched.
  class RideFileRemover
    def initialize(workout)
      @workout = workout
    end

    def call
      @workout.training_plan.with_lock do
        activity = @workout.reload.activity
        if activity&.garmin?
          Activities::Linker.new(activity).unlink!
        else
          activity&.destroy!
        end
      end
    end
  end
end
