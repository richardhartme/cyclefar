module Workouts
  # Attaches an uploaded FIT ride file to a completed workout, replacing any
  # earlier one, with metrics calculated at the workout's completion FTP.
  class RideFileAttacher
    class Rejected < StandardError; end

    CONTENT_TYPE = "application/vnd.ant.fit".freeze

    def initialize(workout:, file:)
      @workout = workout
      @file = file
    end

    def call
      raise Rejected, "Choose a FIT file to upload" unless @file.respond_to?(:read)
      raise Rejected, "Ride files must be 10 MB or smaller" if @file.size > WorkoutActivity::MAXIMUM_FILE_SIZE

      bytes = @file.read
      samples = Fit::Reader.new(bytes).samples

      @workout.training_plan.with_lock do
        @workout.reload
        raise Rejected, "Only completed workouts accept ride files" unless @workout.completed?

        activity = @workout.workout_activity || @workout.build_workout_activity
        activity.assign_metrics(Metrics::RideCalculator.new(samples: samples, ftp_watts: @workout.completed_ftp_watts).call)
        activity.ride_file.attach(io: StringIO.new(bytes), filename: filename, content_type: CONTENT_TYPE)
        activity.save!
        activity
      end
    rescue Fit::Reader::InvalidFile => error
      raise Rejected, error.message
    end

    private

    def filename
      name = @file.respond_to?(:original_filename) ? @file.original_filename.presence : nil
      name || "ride.fit"
    end
  end
end
